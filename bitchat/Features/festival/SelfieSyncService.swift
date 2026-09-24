//
// SelfieSyncService.swift
// bitchat
//
// Propagates the user's selfie to other trip participants via two transports:
//   • Nostr (when reachable) — kind 30078, NIP-78 parameterized replaceable.
//     One canonical "latest selfie" per pubkey, fetched lazily for known peer
//     Nostr pubkeys.
//   • BLE mesh (offline fallback) — request/response messages routed through
//     the existing public-chat broadcast path, with marker prefixes so they
//     never render as chat. Useful off-grid where cellular dies.
//
// The service does not own selfie storage; the per-peer cache lives in
// `PeerSelfieStore` and the user's own selfie in `UserSelfieStore`.
//

import BitFoundation
import Foundation
import BitLogger
#if os(iOS)
import UIKit
#endif

/// Who may receive the user's selfie. User setting (Settings → Profile).
///
/// Physics of the transports, so the labels stay honest:
/// - A BLE *public* message is plaintext to every device in radio range
///   (~10–100 m), whoever asked. So "mutual favorites" cannot be a filter on
///   who we answer — it must switch the transport to per-recipient
///   Noise-encrypted private messages.
/// - Nostr kind-30078 events sit on public relays; anyone who knows your
///   pubkey can fetch them. So only `.everyone` publishes to Nostr.
/// - Selfies already delivered stay on the receivers' devices, and a Nostr
///   copy may persist on relays after switching away from `.everyone`.
enum SelfieShareScope: String, CaseIterable, Identifiable {
    /// Public BLE broadcast + answer any request + publish to Nostr.
    case everyone
    /// Encrypted private message to connected mutual favorites only; no
    /// public broadcast, no Nostr.
    case mutualFavorites
    /// Never send.
    case off

    static let storageKey = "meshy.selfieShareScope"
    static let defaultScope: SelfieShareScope = .everyone

    var id: String { rawValue }

    #if os(iOS)
    var title: String {
        switch self {
        case .everyone: return "Everyone nearby"
        case .mutualFavorites: return "Mutual favorites"
        case .off: return "Nobody"
        }
    }

    var explanation: String {
        switch self {
        case .everyone:
            return "Broadcast over Bluetooth to anyone in range and published to Nostr relays."
        case .mutualFavorites:
            return "Sent encrypted, only to mutual favorites in Bluetooth range. Not published to Nostr."
        case .off:
            return "Your selfie is not sent to anyone."
        }
    }
    #endif

    static var current: SelfieShareScope {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SelfieShareScope.init(rawValue:)) ?? defaultScope
    }
}

/// Nostr pubkeys arrive as npub bech32 (what peers send in favorite
/// notifications, stored in `FavoriteRelationship.peerNostrPublicKey`) or hex
/// (event `pubkey`, relay `authors` filters). Relays and signature checks use
/// hex, so normalize before filtering or comparing.
enum NostrPubkeyFormat {
    static func hex(_ key: String) -> String? {
        if key.lowercased().hasPrefix("npub1") {
            guard let decoded = try? Bech32.decode(key.lowercased()),
                  decoded.hrp == "npub", decoded.data.count == 32 else { return nil }
            return decoded.data.hexEncodedString()
        }
        let lower = key.lowercased()
        guard lower.count == 64, Data(hexString: lower) != nil else { return nil }
        return lower
    }
}

@MainActor
final class SelfieSyncService: ObservableObject {
    static let shared = SelfieSyncService()

    // MARK: - Wire markers (BLE chat-channel control messages)

    /// "Hey, I'd like your selfie." Optional payload: requester's noise key hex
    /// (currently unused). Whether and how we answer depends on
    /// `SelfieShareScope`; the requester is identified by the packet sender.
    static let requestMarker = "\u{1}GE136C-SELFIE-REQ\u{1}"

    /// "Here's my selfie." Body is base64-encoded JPEG. Receivers decode and
    /// hand off to PeerSelfieStore.
    static let responseMarker = "\u{1}GE136C-SELFIE\u{1}"

    /// Closure wired by ChatViewModel that broadcasts a marker-prefixed string
    /// over the BLE-mesh chat transport. Set externally so this service has no
    /// direct dependency on the mesh stack.
    var broadcaster: ((String) -> Void)?

    /// Closure wired by ChatViewModel that sends a marker-prefixed string as a
    /// Noise-encrypted private message to the peer with this Noise key. Used
    /// by `.mutualFavorites`.
    var privateSender: ((String, Data) -> Void)?

    #if os(iOS)
    /// Noise keys of peers currently connected over BLE (recipients when
    /// publishing our own selfie). Wired by ChatViewModel.
    var connectedPeerNoiseKeys: (() -> [Data])?
    #endif

    // MARK: - State

    /// Throttle: don't ask the same peer for their selfie more than once per
    /// cooldown window. Keyed by Noise public key hex.
    private var lastRequestAt: [String: Date] = [:]
    private let requestCooldown: TimeInterval = 60

    /// Track the Nostr subscription IDs we've spun up so we can re-subscribe
    /// when the peer set changes.
    private var currentNostrSubscriptionID: String?
    private var currentNostrAuthors: Set<String> = []

    #if os(iOS)
    /// Loaded lazily because constructing it touches the keychain.
    private lazy var identityBridge = NostrIdentityBridge()
    #endif

    private init() {}

    // MARK: - Public API

    /// Decode and store a peer selfie response received over BLE. Returns true
    /// when the message matched the response marker (so the caller can drop it
    /// from the chat timeline).
    @discardableResult
    func handleIncomingBLEMessage(content: String, senderNoiseKey: Data?, senderNickname: String) -> Bool {
        if content.hasPrefix(Self.requestMarker) {
            SecureLogger.info("🤳 RX selfie REQUEST from \(senderNickname)", category: .session)
            handleSelfieRequest(from: senderNoiseKey)
            return true
        }
        if content.hasPrefix(Self.responseMarker) {
            guard let key = senderNoiseKey else {
                SecureLogger.warning("🤳 RX selfie RESPONSE from \(senderNickname) but no Noise key — dropping", category: .session)
                return true
            }
            let base64 = String(content.dropFirst(Self.responseMarker.count))
            SecureLogger.info("🤳 RX selfie RESPONSE from \(senderNickname) (b64 len=\(base64.count))", category: .session)
            ingestBase64(base64,
                          forNoiseKey: key,
                          nickname: senderNickname,
                          timestamp: Date())
            return true
        }
        return false
    }

    #if os(iOS)
    /// Called when the user takes/replaces their selfie, or on app launch with
    /// an existing selfie. Publishes via Nostr if a relay is reachable and
    /// broadcasts once over BLE so anyone in range refreshes immediately.
    /// iOS-only: the own selfie (`UserSelfieStore`) only exists there.
    func publishOwnSelfie() {
        guard let data = ownSelfieData() else {
            SecureLogger.info("🤳 publishOwnSelfie skipped: no local selfie", category: .session)
            return
        }
        switch SelfieShareScope.current {
        case .everyone:
            SecureLogger.info("🤳 Publishing own selfie (jpeg=\(data.count)B) — Nostr + BLE", category: .session)
            broadcastOwnSelfieOverBLE(data: data)
            publishOwnSelfieToNostr(data: data)
        case .mutualFavorites:
            let recipients = (connectedPeerNoiseKeys?() ?? [])
                .filter { FavoritesPersistenceService.shared.isMutualFavorite($0) }
            SecureLogger.info("🤳 Sending own selfie privately to \(recipients.count) connected mutual favorite(s)", category: .session)
            for key in recipients {
                sendOwnSelfiePrivately(data: data, to: key)
            }
        case .off:
            SecureLogger.info("🤳 publishOwnSelfie skipped: sharing off", category: .session)
        }
    }
    #endif

    /// Ask known peers for their selfies (BLE-only — Nostr fetches are pull, no
    /// request needed). Intended to fire when a new peer comes into mesh range.
    func requestSelfie(fromNoiseKey key: Data) {
        #if os(iOS)
        guard PeerSelfieStore.shared.cachedImage(forNoiseKey: key) == nil else { return }
        #else
        guard !PeerSelfieStore.shared.hasSelfie(forNoiseKey: key) else { return }
        #endif
        let id = key.hexEncodedString()
        if let last = lastRequestAt[id], Date().timeIntervalSince(last) < requestCooldown { return }
        lastRequestAt[id] = Date()
        guard let broadcaster else {
            SecureLogger.warning("🤳 requestSelfie skipped: broadcaster not wired", category: .session)
            return
        }
        // Include our noise key so future versions can target the response.
        let myHex = "" // not yet wired; current responders broadcast to everyone
        SecureLogger.info("🤳 TX selfie REQUEST to peer noiseKey=\(id.prefix(16))…", category: .session)
        broadcaster("\(Self.requestMarker)\(myHex)")
    }

    /// Refresh the Nostr subscription whenever the known peer Nostr pubkey set
    /// changes. Idempotent — only resubscribes when the author set is different.
    func refreshNostrSubscription(authors: Set<String>) {
        // Relays match `authors` against hex pubkeys; favorites store npub.
        let cleaned = Set(authors.compactMap(NostrPubkeyFormat.hex))
        guard cleaned != currentNostrAuthors else { return }

        if let oldID = currentNostrSubscriptionID {
            NostrRelayManager.shared.unsubscribe(id: oldID)
            currentNostrSubscriptionID = nil
        }

        currentNostrAuthors = cleaned
        guard !cleaned.isEmpty else {
            SecureLogger.info("🤳 Selfie sub paused: no known peer Nostr pubkeys yet", category: .session)
            return
        }

        let filter = NostrFilter.tripSelfies(authors: Array(cleaned))
        let subID = TripNamespace.file("selfies")
        currentNostrSubscriptionID = subID
        SecureLogger.info("🤳 Subscribing to selfies for \(cleaned.count) peer pubkey(s)", category: .session)
        NostrRelayManager.shared.subscribe(filter: filter, id: subID) { [weak self] event in
            Task { @MainActor in
                self?.handleNostrSelfieEvent(event)
            }
        }
    }

    // MARK: - Private — incoming

    private func handleSelfieRequest(from requesterNoiseKey: Data?) {
        guard let data = ownSelfieData() else { return }
        switch SelfieShareScope.current {
        case .everyone:
            broadcastOwnSelfieOverBLE(data: data)
        case .mutualFavorites:
            guard let key = requesterNoiseKey,
                  FavoritesPersistenceService.shared.isMutualFavorite(key) else {
                SecureLogger.info("🤳 Ignoring selfie request: requester is not a mutual favorite", category: .session)
                return
            }
            sendOwnSelfiePrivately(data: data, to: key)
        case .off:
            return
        }
    }

    private func handleNostrSelfieEvent(_ event: NostrEvent) {
        guard event.kind == NostrProtocol.EventKind.appData.rawValue else { return }
        guard event.tags.contains(where: { $0.count >= 2 && $0[0] == "d" && $0[1] == NostrProtocol.selfieDTag }) else { return }
        guard event.isValidSignature() else {
            SecureLogger.warning("🤳 Dropped selfie event \(event.id.prefix(8))… — bad signature", category: .security)
            return
        }

        // Map Nostr pubkey back to a Noise public key (our cache is keyed by
        // Noise key). Skip if we don't know who this is — we'd have no way to
        // associate it with a peer.
        guard let noiseKey = noiseKey(forNostrPubkey: event.pubkey) else {
            SecureLogger.info("🤳 Dropped selfie event from \(event.pubkey.prefix(8))… — unknown Nostr pubkey", category: .session)
            return
        }

        guard let payload = SelfiePayload.decode(event.content) else { return }
        guard let imageData = Data(base64Encoded: payload.img) else { return }

        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.created_at))
        let didStore = PeerSelfieStore.shared.store(imageData: imageData,
                                                     forNoiseKey: noiseKey,
                                                     nickname: payload.nick,
                                                     timestamp: timestamp)
        SecureLogger.info("🤳 Stored Nostr selfie for \(payload.nick ?? "?") (\(imageData.count)B, new=\(didStore))", category: .session)
    }

    private func ingestBase64(_ base64: String, forNoiseKey key: Data, nickname: String, timestamp: Date) {
        guard let data = Data(base64Encoded: base64) else { return }
        PeerSelfieStore.shared.store(imageData: data,
                                      forNoiseKey: key,
                                      nickname: nickname,
                                      timestamp: timestamp)
    }

    // MARK: - Private — outgoing

    private func broadcastOwnSelfieOverBLE(data: Data) {
        guard let broadcaster else { return }
        broadcaster(Self.responseBody(for: data))
    }

    private func sendOwnSelfiePrivately(data: Data, to noiseKey: Data) {
        guard let privateSender else {
            SecureLogger.warning("🤳 private selfie send skipped: privateSender not wired", category: .session)
            return
        }
        privateSender(Self.responseBody(for: data), noiseKey)
    }

    private static func responseBody(for data: Data) -> String {
        "\(responseMarker)\(data.base64EncodedString())"
    }

    #if os(iOS)
    private func publishOwnSelfieToNostr(data: Data) {
        guard let identity = try? identityBridge.getCurrentNostrIdentity() else {
            SecureLogger.warning("🤳 Nostr publish skipped: no Nostr identity", category: .session)
            return
        }
        let nick: String? = {
            let trimmed = UserDefaults.standard.string(forKey: "nickname")?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }()
        let payload = SelfiePayload(v: 1, nick: nick, img: data.base64EncodedString())
        guard let json = payload.encode() else { return }
        guard let event = try? NostrProtocol.createSelfieEvent(content: json, senderIdentity: identity) else {
            SecureLogger.error("🤳 Nostr selfie sign failed", category: .session)
            return
        }
        SecureLogger.info("🤳 TX selfie to Nostr (kind=30078 id=\(event.id.prefix(8))… payload=\(json.count)B)", category: .session)
        NostrRelayManager.shared.sendEvent(event)
    }

    // MARK: - Helpers

    /// Largest JPEG we send. The BLE response is marker + base64(JPEG) as one
    /// message, and base64 expands data by 4/3:
    ///   chars = marker (~16) + ceil(bytes / 3) * 4
    /// Limits: InputValidator.Limits.maxMessageLength = 60,000 and the 65,535 B
    /// v1 public-message frame (upstream #1719 drops anything larger). 40,000 B
    /// → 53,352 chars, leaving ~11% headroom under 60,000.
    static let maxSelfieJPEGBytes = 40_000
    #endif

    private func ownSelfieData() -> Data? {
        #if os(iOS)
        guard let image = UserSelfieStore.shared.image else { return nil }
        return Self.cappedJPEG(image, maxBytes: Self.maxSelfieJPEGBytes)
        #else
        return nil
        #endif
    }

    #if os(iOS)
    /// JPEG at the default quality (0.65); if it's over `maxBytes`, lower the
    /// quality, then halve the dimensions, until it fits. A 256 px selfie is
    /// normally 8–20 KB, so this only matters for unusually noisy images.
    static func cappedJPEG(_ image: UIImage, maxBytes: Int) -> Data? {
        var current = image
        for _ in 0..<4 {
            for quality in [0.65, 0.5, 0.35, 0.2] as [CGFloat] {
                guard let data = current.jpegData(compressionQuality: quality) else { return nil }
                if data.count <= maxBytes { return data }
            }
            let size = CGSize(width: current.size.width / 2, height: current.size.height / 2)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let source = current
            current = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        SecureLogger.warning("🤳 Selfie still over \(maxBytes)B after downscaling; not sending", category: .session)
        return nil
    }
    #endif

    private func noiseKey(forNostrPubkey nostrPubkey: String) -> Data? {
        // Event pubkeys are hex; stored favorites are usually npub.
        guard let target = NostrPubkeyFormat.hex(nostrPubkey) else { return nil }
        return FavoritesPersistenceService.shared.favorites.values.first { relationship in
            relationship.peerNostrPublicKey.flatMap(NostrPubkeyFormat.hex) == target
        }?.peerNoisePublicKey
    }
}

// MARK: - Wire payload

private struct SelfiePayload: Codable {
    let v: Int
    let nick: String?
    let img: String

    #if os(iOS)
    func encode() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    #endif

    static func decode(_ content: String) -> SelfiePayload? {
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SelfiePayload.self, from: data)
    }
}
