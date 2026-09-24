//
// TripTimelinePersistence.swift
// Meshy (festy)
//
// On-disk persistence for the mesh public timeline and private DMs, so trip
// chat history survives app restarts (indefinite retention).
//
// Moved here from bitchat/ViewModels/PublicTimelineStore.swift during the
// 2026-09 upstream merge: upstream deleted PublicTimelineStore and made
// `ConversationStore` the single writer of conversation state. This file now
// talks to the store only through its public intent API (`append`,
// `conversationsByID`, `directMessagesByRoutingPeerID`) and its `changes`
// subject, so upstream refactors of the timeline internals don't need to be
// re-merged here.
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

/// On-disk persistence for the mesh timeline. Retention is indefinite; the
/// structure keeps a retention window in case we ever want one again.
@MainActor
final class MeshTimelinePersistence {
    static let shared = MeshTimelinePersistence()

    // Indefinite retention. `.greatestFiniteMagnitude` makes the filters no-ops.
    private let retentionInterval: TimeInterval = .greatestFiniteMagnitude

    /// Debounced save state.
    private var saveTask: DispatchWorkItem?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ge136c-mesh-timeline.json")
    }

    /// Returns persisted mesh messages. Strips trip control packets (location
    /// / selfie markers) that older builds may have written to disk.
    func load() -> [BitchatMessage] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let arr = try? JSONDecoder().decode([BitchatMessage].self, from: data) else { return [] }
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        return arr.filter { $0.timestamp >= cutoff && Self.isPersistable($0) }
    }

    /// Debounced save — waits ~5s after the last call. Use this for "every append".
    func scheduleSave(_ messages: [BitchatMessage]) {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveNow(messages)
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)
    }

    /// Immediate save. Use on app background.
    func saveNow(_ messages: [BitchatMessage]) {
        saveTask?.cancel()
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let filtered = messages.filter { $0.timestamp >= cutoff && Self.isPersistable($0) }
        do {
            let data = try JSONEncoder().encode(filtered)
            try data.write(to: fileURL, options: Self.writeOptions)
        } catch {
            // Silent — persistence is best-effort, not critical.
        }
    }

    /// Protected at rest on iOS; the mesh keeps running while locked, so
    /// "until first unlock" (matches upstream's BridgeDropDedupStore).
    static var writeOptions: Data.WritingOptions {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        return options
    }

    /// Manual wipe (clear chat / panic).
    func clear() {
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Trip control packets never belong in the chat history, and upstream's
    /// "archived echo" rows (id prefix `echo-`) are rebuilt from the gossip
    /// archive each launch, so they are not persisted either.
    static func isPersistable(_ message: BitchatMessage) -> Bool {
        !TripControlMessages.isControlMessage(message.content)
            && !message.id.hasPrefix(BitchatMessage.archivedEchoIDPrefix)
    }
}

/// On-disk persistence for private DMs (indefinite retention). Saves are
/// debounced on every direct-conversation change and flushed on background.
@MainActor
final class PrivateChatsPersistence {
    static let shared = PrivateChatsPersistence()

    private let retentionInterval: TimeInterval = .greatestFiniteMagnitude // indefinite
    private var saveTask: DispatchWorkItem?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ge136c-private-chats.json")
    }

    /// Returns loaded private chats keyed by routing peer ID.
    func load() -> [PeerID: [BitchatMessage]] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        guard let raw = try? JSONDecoder().decode([String: [BitchatMessage]].self, from: data) else { return [:] }
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        var out: [PeerID: [BitchatMessage]] = [:]
        for (k, msgs) in raw {
            let kept = msgs.filter { $0.timestamp >= cutoff }
            guard !kept.isEmpty else { continue }
            out[PeerID(str: k)] = kept
        }
        return out
    }

    func scheduleSave(_ snapshot: @escaping @MainActor () -> [PeerID: [BitchatMessage]]) {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.saveNow(snapshot())
            }
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)
    }

    func saveNow(_ chats: [PeerID: [BitchatMessage]]) {
        saveTask?.cancel()
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        var encoded: [String: [BitchatMessage]] = [:]
        for (peer, msgs) in chats {
            let kept = msgs.filter { $0.timestamp >= cutoff }
            guard !kept.isEmpty else { continue }
            encoded[peer.id] = kept
        }
        do {
            let data = try JSONEncoder().encode(encoded)
            try data.write(to: fileURL, options: MeshTimelinePersistence.writeOptions)
        } catch {
            // Silent — best-effort.
        }
    }

    func clear() {
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Media retention is indefinite for Meshy trips. Upstream's launch-time
/// `BLEIncomingFileStore.expireAgedMedia()` (7 days) is skipped in
/// `AppRuntime.performMediaMaintenance` behind a `// festy:` hook that reads
/// this flag.
enum MediaRetention {
    static let keepMediaIndefinitely = true
    /// Kept for source compatibility with older festy callers; no-op.
    static func pruneNow() { /* indefinite retention — nothing to prune */ }
}

/// Wires `MeshTimelinePersistence` / `PrivateChatsPersistence` to the
/// upstream `ConversationStore`: restores history once at startup, then saves
/// (debounced) whenever the mesh or a direct conversation changes, and flushes
/// on background. Owned by `ChatViewModel` via `festyConfigureTripLayer()`.
@MainActor
final class TripTimelinePersistenceController {
    static let shared = TripTimelinePersistenceController()

    private weak var conversations: ConversationStore?
    private var cancellables = Set<AnyCancellable>()
    private var isRestoring = false

    private init() {}

    /// Restore persisted history into the store. Must run before upstream's
    /// archived-echo seeding (which only seeds an empty mesh timeline).
    func restore(into viewModel: ChatViewModel) {
        isRestoring = true
        defer { isRestoring = false }

        for message in MeshTimelinePersistence.shared.load() {
            _ = viewModel.appendPublicMessage(message, to: .mesh)
        }
        for (peerID, messages) in PrivateChatsPersistence.shared.load() {
            for message in messages {
                _ = viewModel.appendPrivateMessage(message, to: peerID)
            }
        }
    }

    /// Start observing the store; idempotent per store instance.
    func bind(to conversations: ConversationStore) {
        guard self.conversations !== conversations else { return }
        cancellables.removeAll()
        self.conversations = conversations

        conversations.changes
            .sink { [weak self] change in
                self?.handle(change)
            }
            .store(in: &cancellables)

        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.flushNow()
            }
            .store(in: &cancellables)
        #endif
    }

    func flushNow() {
        guard let conversations else { return }
        MeshTimelinePersistence.shared.saveNow(conversations.conversationsByID[.mesh]?.messages ?? [])
        PrivateChatsPersistence.shared.saveNow(conversations.directMessagesByRoutingPeerID())
    }

    /// Panic wipe: drop the on-disk copies immediately (no debounce).
    func wipe() {
        MeshTimelinePersistence.shared.clear()
        PrivateChatsPersistence.shared.clear()
    }

    private func handle(_ change: ConversationChange) {
        guard !isRestoring, let conversations else { return }
        let id: ConversationID
        switch change {
        case .appended(let changed, _),
             .updated(let changed, _),
             .statusChanged(let changed, _, _),
             .messageRemoved(let changed, _),
             .cleared(let changed),
             .removed(let changed),
             .unreadChanged(let changed, _):
            id = changed
        case .migrated(_, let destination):
            id = destination
        }

        switch id {
        case .mesh:
            if case .cleared = change {
                // "clear chat log" must not come back on next launch.
                MeshTimelinePersistence.shared.clear()
                return
            }
            if case .unreadChanged = change { return }
            MeshTimelinePersistence.shared.scheduleSave(conversations.conversationsByID[.mesh]?.messages ?? [])
        case .direct:
            if case .unreadChanged = change { return }
            PrivateChatsPersistence.shared.scheduleSave { [weak conversations] in
                conversations?.directMessagesByRoutingPeerID() ?? [:]
            }
        case .geohash:
            // Geohash timelines are not persisted (same as pre-merge festy).
            return
        }
    }
}
