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
//     never render as chat. Useful in the Sierras where cellular dies.
//
// The service does not own selfie storage; the per-peer cache lives in
// `PeerSelfieStore` and the user's own selfie in `UserSelfieStore`.
//

import Foundation
import BitLogger
#if os(iOS)
import UIKit
#endif

@MainActor
final class SelfieSyncService: ObservableObject {
    static let shared = SelfieSyncService()

    // MARK: - Wire markers (BLE chat-channel control messages)

    /// "Hey, I'd like your selfie." Optional payload: requester's noise key hex
    /// (currently unused — every peer with a selfie just responds).
    static let requestMarker = "\u{1}GE136C-SELFIE-REQ\u{1}"

    /// "Here's my selfie." Body is base64-encoded JPEG. Receivers decode and
    /// hand off to PeerSelfieStore.
    static let responseMarker = "\u{1}GE136C-SELFIE\u{1}"

    /// Closure wired by ChatViewModel that broadcasts a marker-prefixed string
    /// over the BLE-mesh chat transport. Set externally so this service has no
    /// direct dependency on the mesh stack.
    var broadcaster: ((String) -> Void)?

    // MARK: - State

    /// Throttle: don't ask the same peer for their selfie more than once per
    /// cooldown window. Keyed by Noise public key hex.
    private var lastRequestAt: [String: Date] = [:]
    private let requestCooldown: TimeInterval = 60

    /// Track the Nostr subscription IDs we've spun up so we can re-subscribe
    /// when the peer set changes.
    private var currentNostrSubscriptionID: String?
    private var currentNostrAuthors: Set<String> = []

    /// Loaded lazily because constructing it touches the keychain.
    private lazy var identityBridge = NostrIdentityBridge()

    private init() {}

    // MARK: - Public API

    /// Decode and store a peer selfie response received over BLE. Returns true
    /// when the message matched the response marker (so the caller can drop it
    /// from the chat timeline).
    @discardableResult
    func handleIncomingBLEMessage(content: String, senderNoiseKey: Data?, senderNickname: String) -> Bool {
        if content.hasPrefix(Self.requestMarker) {
            SecureLogger.info("🤳 RX selfie REQUEST from \(senderNickname)", category: .session)
            handleSelfieRequest()
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

    /// Called when the user takes/replaces their selfie, or on app launch with
    /// an existing selfie. Publishes via Nostr if a relay is reachable and
    /// broadcasts once over BLE so anyone in range refreshes immediately.
    func publishOwnSelfie() {
        guard let data = ownSelfieData() else {
            SecureLogger.info("🤳 publishOwnSelfie skipped: no local selfie", category: .session)
            return
        }
        SecureLogger.info("🤳 Publishing own selfie (jpeg=\(data.count)B) — Nostr + BLE", category: .session)
        broadcastOwnSelfieOverBLE(data: data)
        publishOwnSelfieToNostr(data: data)
    }

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
        let cleaned = Set(authors.filter { !$0.isEmpty })
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
        let subID = "ge136c-selfies"
        currentNostrSubscriptionID = subID
        SecureLogger.info("🤳 Subscribing to selfies for \(cleaned.count) peer pubkey(s)", category: .session)
        NostrRelayManager.shared.subscribe(filter: filter, id: subID) { [weak self] event in
            Task { @MainActor in
                self?.handleNostrSelfieEvent(event)
            }
        }
    }

    // MARK: - Private — incoming

    private func handleSelfieRequest() {
        guard let data = ownSelfieData() else { return }
        broadcastOwnSelfieOverBLE(data: data)
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
        let body = "\(Self.responseMarker)\(data.base64EncodedString())"
        broadcaster(body)
    }

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

    private func ownSelfieData() -> Data? {
        #if os(iOS)
        guard let image = UserSelfieStore.shared.image else { return nil }
        return image.jpegData(compressionQuality: 0.65)
        #else
        return nil
        #endif
    }

    private func noiseKey(forNostrPubkey nostrPubkey: String) -> Data? {
        let lower = nostrPubkey.lowercased()
        for relationship in FavoritesPersistenceService.shared.favorites.values {
            if relationship.peerNostrPublicKey?.lowercased() == lower {
                return relationship.peerNoisePublicKey
            }
        }
        return nil
    }
}

// MARK: - Wire payload

private struct SelfiePayload: Codable {
    let v: Int
    let nick: String?
    let img: String

    func encode() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ content: String) -> SelfiePayload? {
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SelfiePayload.self, from: data)
    }
}
