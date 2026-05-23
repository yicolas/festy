//
// PublicTimelineStore.swift
// bitchat
//
// Maintains mesh and geohash public timelines with simple caps and helpers.
//

import Foundation

/// On-disk persistence for the mesh timeline with a 30-day rolling window.
/// Trip chat history survives app restarts; older messages are pruned on save/load.
@MainActor
final class MeshTimelinePersistence {
    static let shared = MeshTimelinePersistence()

    // Indefinite retention. Set retentionInterval to .greatestFiniteMagnitude
    // so the filters become no-ops; structure preserved in case we ever
    // want to re-enable a window.
    private let retentionInterval: TimeInterval = .greatestFiniteMagnitude // indefinite

    /// Debounced save state.
    private var saveTask: DispatchWorkItem?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ge136c-mesh-timeline.json")
    }

    /// Returns persisted mesh messages with anything older than 30 days dropped.
    func load() -> [BitchatMessage] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let arr = try? JSONDecoder().decode([BitchatMessage].self, from: data) else { return [] }
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        return arr.filter { $0.timestamp >= cutoff }
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

    /// Immediate save, applies the 30-day prune. Use on app background.
    func saveNow(_ messages: [BitchatMessage]) {
        saveTask?.cancel()
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let filtered = messages.filter { $0.timestamp >= cutoff }
        do {
            let data = try JSONEncoder().encode(filtered)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent — persistence is best-effort, not critical.
        }
    }

    /// Manual wipe (e.g. for "clear chat history" UI).
    func clear() {
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// On-disk persistence for private DMs with the same 7-day rolling window
/// as the public timeline. Saves are coarse-grained (periodic + on background)
/// rather than per-append because PrivateChat mutations are scattered.
@MainActor
final class PrivateChatsPersistence {
    static let shared = PrivateChatsPersistence()

    private let retentionInterval: TimeInterval = .greatestFiniteMagnitude // indefinite

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ge136c-private-chats.json")
    }

    /// Returns loaded private chats, pruned to the retention window.
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

    func saveNow(_ chats: [PeerID: [BitchatMessage]]) {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        var encoded: [String: [BitchatMessage]] = [:]
        for (peer, msgs) in chats {
            let kept = msgs.filter { $0.timestamp >= cutoff }
            guard !kept.isEmpty else { continue }
            encoded[peer.id] = kept
        }
        do {
            let data = try JSONEncoder().encode(encoded)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent — best-effort.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Media retention is now indefinite — `pruneNow` is a no-op so existing
/// callers stay compatible.
enum MediaRetention {
    static func pruneNow() { /* indefinite retention — nothing to prune */ }
}

struct PublicTimelineStore {
    private var meshTimeline: [BitchatMessage] = []
    private var geohashTimelines: [String: [BitchatMessage]] = [:]
    private var pendingGeohashSystemMessages: [String] = []

    private let meshCap: Int
    private let geohashCap: Int

    init(meshCap: Int, geohashCap: Int) {
        self.meshCap = meshCap
        self.geohashCap = geohashCap
    }

    mutating func append(_ message: BitchatMessage, to channel: ChannelID) {
        switch channel {
        case .mesh:
            guard !meshTimeline.contains(where: { $0.id == message.id }) else { return }
            meshTimeline.append(message)
            trimMeshTimelineIfNeeded()
        case .location(let channel):
            append(message, toGeohash: channel.geohash)
        }
    }

    mutating func append(_ message: BitchatMessage, toGeohash geohash: String) {
        var timeline = geohashTimelines[geohash] ?? []
        guard !timeline.contains(where: { $0.id == message.id }) else { return }
        timeline.append(message)
        trimGeohashTimelineIfNeeded(&timeline)
        geohashTimelines[geohash] = timeline
    }

    /// Append message if absent, returning true when stored.
    mutating func appendIfAbsent(_ message: BitchatMessage, toGeohash geohash: String) -> Bool {
        var timeline = geohashTimelines[geohash] ?? []
        guard !timeline.contains(where: { $0.id == message.id }) else { return false }
        timeline.append(message)
        trimGeohashTimelineIfNeeded(&timeline)
        geohashTimelines[geohash] = timeline
        return true
    }

    mutating func messages(for channel: ChannelID) -> [BitchatMessage] {
        switch channel {
        case .mesh:
            return meshTimeline
        case .location(let channel):
            let cleaned = geohashTimelines[channel.geohash]?.cleanedAndDeduped() ?? []
            geohashTimelines[channel.geohash] = cleaned
            return cleaned
        }
    }

    mutating func clear(channel: ChannelID) {
        switch channel {
        case .mesh:
            meshTimeline.removeAll()
        case .location(let channel):
            geohashTimelines[channel.geohash] = []
        }
    }

    @discardableResult
    mutating func removeMessage(withID id: String) -> BitchatMessage? {
        if let index = meshTimeline.firstIndex(where: { $0.id == id }) {
            return meshTimeline.remove(at: index)
        }

        for key in Array(geohashTimelines.keys) {
            var timeline = geohashTimelines[key] ?? []
            if let index = timeline.firstIndex(where: { $0.id == id }) {
                let removed = timeline.remove(at: index)
                geohashTimelines[key] = timeline.isEmpty ? nil : timeline
                return removed
            }
        }

        return nil
    }

    mutating func removeMessages(in geohash: String, where predicate: (BitchatMessage) -> Bool) {
        var timeline = geohashTimelines[geohash] ?? []
        timeline.removeAll(where: predicate)
        geohashTimelines[geohash] = timeline.isEmpty ? nil : timeline
    }

    mutating func mutateGeohash(_ geohash: String, _ transform: (inout [BitchatMessage]) -> Void) {
        var timeline = geohashTimelines[geohash] ?? []
        transform(&timeline)
        geohashTimelines[geohash] = timeline.isEmpty ? nil : timeline
    }

    mutating func queueGeohashSystemMessage(_ content: String) {
        pendingGeohashSystemMessages.append(content)
    }

    mutating func drainPendingGeohashSystemMessages() -> [String] {
        defer { pendingGeohashSystemMessages.removeAll(keepingCapacity: false) }
        return pendingGeohashSystemMessages
    }

    func geohashKeys() -> [String] {
        Array(geohashTimelines.keys)
    }

    private mutating func trimMeshTimelineIfNeeded() {
        guard meshTimeline.count > meshCap else { return }
        meshTimeline = Array(meshTimeline.suffix(meshCap))
    }

    private func trimGeohashTimelineIfNeeded(_ timeline: inout [BitchatMessage]) {
        guard timeline.count > geohashCap else { return }
        timeline = Array(timeline.suffix(geohashCap))
    }
}
