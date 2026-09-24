//
// ChatViewModel+Trip.swift
// Meshy (festy)
//
// Every festy (trip layer) behavior that used to live inline in
// ChatViewModel.swift. Upstream split ChatViewModel into coordinators, so the
// festy code now lives here and core files only carry one-line `// festy:`
// hooks that call into this file:
//
//   ChatViewModel.init              → festyConfigureTripLayer()
//   ChatViewModel.sendMessage       → festyScopedOutgoingContent(_:)
//   ChatViewModel.panicClearAllData → TripTimelinePersistenceController.wipe()
//   ChatTransportEventCoordinator   → festyInterceptTripControlMessage(...)
//                                      (public mesh message delivery, both paths)
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import BitLogger
import Combine
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Trip control messages

/// Marker-prefixed public mesh messages used by the trip layer as a control
/// channel (friend location, selfie request/response). They are routed to
/// their services and must never render as chat or be persisted.
enum TripControlMessages {
    @MainActor
    static func isControlMessage(_ content: String) -> Bool {
        content.hasPrefix(FriendLocationService.locationMarker)
            || content.hasPrefix(SelfieSyncService.requestMarker)
            || content.hasPrefix(SelfieSyncService.responseMarker)
    }
}

// MARK: - Trip UI state

/// Trip-layer state that used to be `@Published` stored properties on
/// `ChatViewModel`. Extensions can't add stored properties, so it lives here
/// and `ChatViewModel` forwards to it (sending `objectWillChange` so views
/// observing the view model still refresh).
@MainActor
final class TripChatState: ObservableObject {
    static let shared = TripChatState()
    static let hasChosenNicknameKey = "bitchat.hasChosenNickname"

    /// When non-nil, the public timeline shows only messages whose content
    /// contains this hashtag (case-insensitive). Set via the trip channel list.
    @Published var hashtagFilter: String?

    /// Whether the user completed the "pick your name" onboarding prompt.
    @Published var hasChosenNickname: Bool

    /// Set by `festyConfigureTripLayer()` so trip views that are not handed a
    /// `ChatViewModel` (e.g. LocationChannelsSheet, which upstream presents
    /// with only its own models) can still read the mesh timeline.
    weak var chatViewModel: ChatViewModel?

    /// Set by MeshyApp on appear; lets trip views present upstream sheets
    /// (e.g. AppInfoView) with the runtime's models injected explicitly.
    weak var appRuntime: AppRuntime?

    /// The mesh public timeline (used to discover `#car-{driver}` chats).
    func meshMessages() -> [BitchatMessage] {
        chatViewModel?.conversations.conversationsByID[.mesh]?.messages ?? []
    }

    private init() {
        hasChosenNickname = UserDefaults.standard.bool(forKey: Self.hasChosenNicknameKey)
    }
}

extension ChatViewModel {

    // MARK: Trip UI state (forwarded)

    @MainActor
    var hashtagFilter: String? {
        get { TripChatState.shared.hashtagFilter }
        set {
            objectWillChange.send()
            TripChatState.shared.hashtagFilter = newValue
        }
    }

    @MainActor
    var hasChosenNickname: Bool {
        TripChatState.shared.hasChosenNickname
    }

    @MainActor
    func confirmNickname(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nickname = trimmed.isEmpty ? "anon\(Int.random(in: 1000...9999))" : trimmed
        saveNickname()
        UserDefaults.standard.set(true, forKey: TripChatState.hasChosenNicknameKey)
        objectWillChange.send()
        TripChatState.shared.hasChosenNickname = true
    }

    // MARK: Startup (called once from ChatViewModel.init)

    /// Wires the trip services to the mesh transport, restores persisted trip
    /// history, seeds #meals placeholders and starts trip Nostr subscriptions.
    /// Skipped under tests so upstream's ChatViewModel tests see a clean store.
    @MainActor
    func festyConfigureTripLayer() {
        guard !TestEnvironment.isRunningTests else { return }
        TripChatState.shared.chatViewModel = self

        // Locations and selfies travel as marker-prefixed public mesh
        // messages (BLE). They go straight to the transport — not through
        // `sendMessage` — so they skip the timeline, the hashtag scoping,
        // and the mesh bridge.
        FriendLocationService.shared.broadcaster = { [weak self] content in
            guard let self else { return }
            self.meshService.sendMessage(content, mentions: [], messageID: UUID().uuidString, timestamp: Date())
        }
        SelfieSyncService.shared.broadcaster = { [weak self] content in
            guard let self else { return }
            self.meshService.sendMessage(content, mentions: [], messageID: UUID().uuidString, timestamp: Date())
        }

        // Restore persisted mesh timeline + DMs before upstream's archived
        // echo seeding runs (it only seeds an untouched mesh timeline).
        TripTimelinePersistenceController.shared.restore(into: self)
        seedMealPlaceholdersIfNeeded()
        TripTimelinePersistenceController.shared.bind(to: conversations)
        bindTripChannelNotifications()

        // Publish our selfie once and prime the Nostr selfie subscription;
        // pull every trip-note pin and republish ours.
        Task { @MainActor in
            festyRefreshSelfieSubscription()
            #if os(iOS)
            if UserSelfieStore.shared.image != nil {
                SelfieSyncService.shared.publishOwnSelfie()
            }
            #endif
            TripNotesService.shared.startNostrSubscription()
            TripNotesService.shared.republishAllLocal()
        }
    }

    // MARK: Outgoing (called from ChatViewModel.sendMessage)

    /// Per-channel input scope: when a trip hashtag filter is active on the
    /// mesh channel, append the tag so the user just types and sends.
    /// Commands and private chats are left untouched.
    @MainActor
    func festyScopedOutgoingContent(_ content: String) -> String {
        guard !content.hasPrefix("/"),
              selectedPrivateChatPeer == nil,
              case .mesh = activeChannel,
              let tag = hashtagFilter, !tag.isEmpty else { return content }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return content }
        if trimmed.range(of: tag, options: .caseInsensitive) != nil { return trimmed }
        return "\(trimmed) \(tag)"
    }

    // MARK: Incoming (called from ChatTransportEventCoordinator)

    /// Routes trip control packets (location / selfie markers) to their
    /// services. Returns `true` when the message was consumed and must not
    /// reach the timeline, notifications, mentions or haptics. For ordinary
    /// public mesh messages it auto-favorites the sender (so the trip map
    /// works without manual favoriting) and returns `false`.
    @MainActor
    func festyInterceptTripControlMessage(content: String, senderPeerID: PeerID?, senderNickname: String) -> Bool {
        let noiseKey: Data? = senderPeerID.flatMap { unifiedPeer(for: $0)?.noisePublicKey }
        let senderIsBlocked = senderPeerID.map { isPeerBlocked($0) } ?? false

        // Blocked senders: swallow their control packets; let ordinary
        // messages fall through to upstream's block gate (never auto-favorite).
        if senderIsBlocked {
            return TripControlMessages.isControlMessage(content)
        }

        if content.hasPrefix(FriendLocationService.locationMarker) {
            FriendLocationService.shared.ingestLocationMessage(
                content: content,
                senderNoiseKey: noiseKey,
                senderNickname: senderNickname
            )
            return true
        }

        if content.hasPrefix(SelfieSyncService.requestMarker)
            || content.hasPrefix(SelfieSyncService.responseMarker) {
            SelfieSyncService.shared.handleIncomingBLEMessage(
                content: content,
                senderNoiseKey: noiseKey,
                senderNickname: senderNickname
            )
            return true
        }

        if let noiseKey, senderPeerID != meshService.myPeerID {
            autoFavoriteTripPeer(noiseKey: noiseKey, nickname: senderNickname)
        }
        return false
    }

    /// Silently adds the sender of any non-self mesh message to favorites so
    /// the map and friend features work without each user manually favoriting
    /// everyone in the group. Idempotent.
    @MainActor
    private func autoFavoriteTripPeer(noiseKey: Data, nickname senderNickname: String) {
        guard senderNickname != "system", senderNickname != nickname else { return }

        // Ask this peer for their selfie if we don't already have it cached
        // (BLE only; Nostr selfies are pulled by subscription).
        SelfieSyncService.shared.requestSelfie(fromNoiseKey: noiseKey)

        let status = FavoritesPersistenceService.shared.getFavoriteStatus(for: noiseKey)
        if status?.isFavorite == true {
            festyRefreshSelfieSubscription()
            return
        }
        let nostrKey = status?.peerNostrPublicKey ?? idBridge.getNostrPublicKey(for: noiseKey)
        FavoritesPersistenceService.shared.addFavorite(
            peerNoisePublicKey: noiseKey,
            peerNostrPublicKey: nostrKey,
            peerNickname: senderNickname
        )
        festyRefreshSelfieSubscription()
    }

    /// Re-subscribe to the Nostr selfie feed using the current set of known
    /// peer Nostr pubkeys (from favorites). Idempotent inside SelfieSyncService.
    @MainActor
    func festyRefreshSelfieSubscription() {
        let authors = Set(FavoritesPersistenceService.shared.favorites.values
            .compactMap { $0.peerNostrPublicKey?.lowercased() }
            .filter { !$0.isEmpty })
        SelfieSyncService.shared.refreshNostrSubscription(authors: authors)
    }

    // MARK: Trip channel notifications

    /// Fires a local notification when a public message mentions a trip
    /// channel hashtag. Driven by the store's change stream so it sees every
    /// message that actually lands in a public timeline (after upstream's
    /// block / rate-limit / dedup gates), and never sees restored history.
    @MainActor
    private func bindTripChannelNotifications() {
        conversations.changes
            .sink { [weak self] change in
                guard let self,
                      case .appended(let id, let message) = change else { return }
                switch id {
                case .mesh, .geohash:
                    self.notifyForTripChannelIfNeeded(message)
                case .direct:
                    return
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func notifyForTripChannelIfNeeded(_ message: BitchatMessage) {
        guard message.sender != "system",
              message.sender != nickname,
              message.senderPeerID != meshService.myPeerID,
              !message.isArchivedEcho,
              !message.id.hasPrefix("meal-seed-") else { return }
        let channels = TripScheduleManager.shared.channels
        guard !channels.isEmpty else { return }
        let body = message.content

        // If the app is foreground AND the user is filtered to this channel,
        // suppress (they can see it inline). Other channels still fire.
        #if os(iOS)
        let activeFilter = hashtagFilter
        let suppressActiveChannel: (String) -> Bool = { channelName in
            guard UIApplication.shared.applicationState == .active else { return false }
            guard let active = activeFilter, !active.isEmpty else { return false }
            return active.caseInsensitiveCompare(channelName) == .orderedSame
        }
        #else
        let suppressActiveChannel: (String) -> Bool = { _ in false }
        #endif

        for channel in channels where body.range(of: channel.name, options: .caseInsensitive) != nil {
            if suppressActiveChannel(channel.name) { return }
            NotificationService.shared.sendChannelMessageNotification(
                channel: channel.name,
                sender: message.sender,
                message: body
            )
            return // one notification per message even if multiple tags
        }
    }

    // MARK: #meals seed

    /// Inserts one-time #meals placeholder messages into the mesh timeline,
    /// anchored to the trip's actual meal times in America/Los_Angeles.
    /// Bumping the seed version regenerates them.
    @MainActor
    func seedMealPlaceholdersIfNeeded() {
        let defaults = UserDefaults.standard
        let seedKey = "ge136c.mealPlaceholdersSeededVersion"
        // Bump when meal contents change so existing users get the update.
        // v2: replaced dinner placeholders with full menus from the dinners CSV.
        // v3: removed breakfast/lunch placeholders — only dinners are seeded
        //     because the rest are user-coordinated in chat.
        let currentVersion = 3
        let stored = defaults.integer(forKey: seedKey)
        guard stored < currentVersion else { return }

        // When re-seeding (stored > 0), evict the previous version's seed
        // messages first so the new ones aren't deduped by ID match AND so
        // dropped slots (breakfast/lunch) don't linger after upgrade. IDs
        // follow the pattern `meal-seed-<date>-<meal>`.
        if stored > 0 {
            let dateStrings = ["2026-05-29", "2026-05-30", "2026-05-31", "2026-06-01"]
            let meals = ["breakfast", "lunch", "dinner"]
            for date in dateStrings {
                for meal in meals {
                    _ = conversations.removeMessage(withID: "meal-seed-\(date)-\(meal)", from: .mesh)
                }
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        struct MealSlot {
            let date: String        // yyyy-MM-dd
            let time: String        // HH:mm 24h
            let day: String         // "Friday"
            let meal: String        // "dinner"
            let placeholder: String // user-facing text
        }

        // Dinner menus from the 2026 dinners list. Listing ingredients without
        // amounts + the obvious allergens so people with restrictions can plan.
        let fajitas = """
        🌯 Fajitas
        Ingredients: pre-cooked beef strips, bell peppers, onions, beans, Mexican cheese, sour cream, guacamole, salsa, vegan meat option, tortillas, avocado, cilantro, tortilla chips, jalapeño, tomatoes
        Allergens: dairy (cheese, sour cream), gluten (tortillas/chips may be wheat or cross-contaminated)
        """
        let alfredo = """
        🍝 Pasta Alfredo
        Ingredients: pre-cooked chicken, alfredo sauce, zucchini, summer squash, vegetarian sausage, mushrooms, pasta, spinach
        Allergens: dairy (alfredo sauce — cream/butter/parmesan), gluten (pasta), possibly soy/wheat in vegetarian sausage
        """
        let kebabs = """
        🥙 Kebabs + Salad
        Ingredients: chicken thighs/breasts, tofu, Greek yogurt, bell peppers, cherry tomatoes, red onion, cilantro, mint, lemon, zucchini, summer squash, eggplant, pita, tzatziki, hummus, cucumber, olives, feta cheese
        Spices: honey, cumin, turmeric, salt, pepper, olive oil, garlic powder, onion powder, chili powder, paprika
        Allergens: dairy (yogurt, tzatziki, feta), gluten (pita), sesame (hummus/tahini), soy (tofu)
        """

        // Dinners only — breakfast/lunch coordination happens organically in chat.
        let slots: [MealSlot] = [
            .init(date: "2026-05-29", time: "18:30", day: "Friday",   meal: "dinner", placeholder: fajitas),
            .init(date: "2026-05-30", time: "18:30", day: "Saturday", meal: "dinner", placeholder: alfredo),
            .init(date: "2026-05-31", time: "18:30", day: "Sunday",   meal: "dinner", placeholder: kebabs)
        ]

        for slot in slots {
            guard let stamp = formatter.date(from: "\(slot.date) \(slot.time)") else { continue }
            let id = "meal-seed-\(slot.date)-\(slot.meal)"
            // For multi-line menus, keep the channel tag on the header line so
            // the channel filter regex hits it without trailing punctuation.
            let isMultiline = slot.placeholder.contains("\n")
            let body: String = isMultiline
                ? "\(slot.day) \(slot.meal) #meals\n\(slot.placeholder)"
                : "\(slot.day) \(slot.meal): \(slot.placeholder) #meals"
            let message = BitchatMessage(
                id: id,
                sender: "system",
                content: body,
                timestamp: stamp,
                isRelay: false
            )
            _ = appendPublicMessage(message, to: .mesh)
        }
        defaults.set(currentVersion, forKey: seedKey)
        // Persist so the seeds aren't re-injected on the next launch.
        MeshTimelinePersistence.shared.saveNow(conversations.conversationsByID[.mesh]?.messages ?? [])
    }
}

// MARK: - Transport-event hook

extension ChatTransportEventContext {
    /// Default for test contexts: nothing is intercepted. `ChatViewModel`
    /// overrides via its conformance (the requirement is declared on the
    /// protocol, so dispatch is dynamic).
    @MainActor
    func festyInterceptTripControlMessage(content: String, senderPeerID: PeerID?, senderNickname: String) -> Bool {
        false
    }
}

// MARK: - Timeline filter (used by MessageListView)

/// What the chat list shows: trip control packets are always hidden, and on
/// public timelines the active trip hashtag filter applies.
enum TripTimelineFilter {
    @MainActor
    static func visibleMessages(_ base: [BitchatMessage], hashtagFilter: String?) -> [BitchatMessage] {
        // Defensive: location + selfie control packets must never render as chat.
        let rawMessages = base.filter { !TripControlMessages.isControlMessage($0.content) }

        guard let tag = hashtagFilter, !tag.isEmpty else { return rawMessages }

        // #main is a catch-all: show everything EXCEPT messages tagged with a
        // #car-X that isn't this user's own car AND any #meals messages (those
        // live exclusively in the #meals channel so they don't clog the feed).
        if tag.caseInsensitiveCompare("#main") == .orderedSame {
            let myCarTag = CarAssignmentStore.shared.assignedTag?.lowercased()
            let carRegex = try? NSRegularExpression(pattern: "#car-([a-zA-Z0-9-]+)", options: .caseInsensitive)
            return rawMessages.filter { msg in
                let content = msg.content
                if content.range(of: "#meals", options: .caseInsensitive) != nil {
                    return false
                }
                guard let regex = carRegex else { return true }
                let nsRange = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, options: [], range: nsRange)
                if matches.isEmpty { return true }
                for match in matches {
                    if let r = Range(match.range(at: 1), in: content) {
                        let foundTag = "#car-" + String(content[r]).lowercased()
                        if let mine = myCarTag, mine == foundTag {
                            return true
                        }
                    }
                }
                return false
            }
        }

        return rawMessages.filter { $0.content.range(of: tag, options: .caseInsensitive) != nil }
    }
}
