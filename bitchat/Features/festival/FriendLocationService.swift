//
// FriendLocationService.swift
// bitchat
//
// Location sharing service for mutual favorites on trips
//

import BitFoundation
import Foundation
import CoreLocation
import Combine
import CryptoKit

/// Represents a friend's shared location
struct FriendLocation: Identifiable, Equatable {
    let id: Data  // Noise public key
    let nickname: String
    let coordinate: CLLocationCoordinate2D
    let accuracy: CLLocationAccuracy
    let timestamp: Date
    let isStale: Bool  // True if location is older than staleness threshold

    static func == (lhs: FriendLocation, rhs: FriendLocation) -> Bool {
        lhs.id == rhs.id && lhs.timestamp == rhs.timestamp
    }
}

/// Location update packet payload
/// Sent via BLE mesh to mutual favorites only
struct LocationSharePayload: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double  // meters
    let timestamp: UInt64  // milliseconds since epoch (UTC)

    /// Encode to compact binary format (28 bytes)
    /// Layout: lat (8 BE) + lon (8 BE) + accuracy (4 BE float) + timestamp (8 BE UInt64)
    func toData() -> Data {
        var data = Data()

        var latBits = latitude.bitPattern.bigEndian
        var lonBits = longitude.bitPattern.bigEndian
        var accBits = Float(accuracy).bitPattern.bigEndian
        var ts = timestamp.bigEndian

        withUnsafeBytes(of: &latBits) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &lonBits) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &accBits) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &ts) { data.append(contentsOf: $0) }

        return data
    }

    /// Decode from compact binary format
    static func fromData(_ data: Data) -> LocationSharePayload? {
        // Expect exactly 28 bytes (or at least that many)
        guard data.count >= 28 else { return nil }

        return data.withUnsafeBytes { raw -> LocationSharePayload? in
            let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            // Read 8 bytes -> Double (big-endian)
            let latBits = base.withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
            let lonBits = base.advanced(by: 8).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
            let accBits = base.advanced(by: 16).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
            let tsBits = base.advanced(by: 20).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }

            let lat = Double(bitPattern: UInt64(bigEndian: latBits))
            let lon = Double(bitPattern: UInt64(bigEndian: lonBits))
            let acc = Float(bitPattern: UInt32(bigEndian: accBits))
            let ts = UInt64(bigEndian: tsBits)

            return LocationSharePayload(latitude: lat, longitude: lon, accuracy: Double(acc), timestamp: ts)
        }
    }
}

/// Simple AEAD helpers using CryptoKit (symmetric key).
/// TODO: Replace symmetric key usage by deriving an AEAD key per-peer from the app's Noise state.
struct AEAD {
    static func encrypt(payload: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(payload, using: key)
        return sealed.combined ?? Data()
    }

    static func decrypt(_ combined: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

/// Manages location sharing with mutual favorites
@MainActor
class FriendLocationService: NSObject, ObservableObject {
    static let shared = FriendLocationService()

    /// Wire-level marker prefix for location packets sent as chat-channel
    /// messages. The leading control char ensures no collision with real text.
    static let locationMarker = "\u{1}GE136C-LOC\u{1}"

    /// Closure invoked when this device wants to broadcast its location.
    /// `ChatViewModel` sets this in init so we can fan the encoded string out
    /// over the existing BLE-mesh chat transport.
    var broadcaster: ((String) -> Void)?

    /// How this device sends its location (user setting, Settings → Location).
    /// Cross-platform with fest-mesh-android #89 (`ShareMode`).
    ///
    /// - `broadcast`: plaintext BLE public message; anyone in radio range can
    ///   read the coordinates.
    /// - `encrypted`: one Noise-encrypted copy (NoisePayloadType 0x30) per
    ///   connected mutual favorite. Coordinates are hidden from everyone else,
    ///   but a sniffer can still see *that* you are sending (timing, size,
    ///   recipient count). Peers without an established Noise session miss
    ///   that interval (a handshake is started for the next one).
    enum ShareMode: String, CaseIterable, Identifiable {
        case broadcast
        case encrypted

        static let storageKey = "meshy.friendLocationShareMode"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .broadcast: return "Anyone nearby"
            case .encrypted: return "Mutual favorites (encrypted)"
            }
        }

        var explanation: String {
            switch self {
            case .broadcast:
                return "Anyone nearby can read your location."
            case .encrypted:
                return "Only mutual favorites in Bluetooth range can read your location. Others can still tell that you're sending."
            }
        }

        static var current: ShareMode {
            UserDefaults.standard.string(forKey: storageKey).flatMap(ShareMode.init(rawValue:)) ?? .broadcast
        }
    }

    /// Sends the marker+CSV string encrypted to each recipient (`.encrypted`
    /// mode). Wired by ChatViewModel to `Transport.sendEncryptedLocationShare`.
    var encryptedBroadcaster: ((String, [PeerID]) -> Void)?

    /// Recipients for `.encrypted` mode: connected mutual favorites. Wired by
    /// ChatViewModel.
    var encryptedRecipients: (() -> [PeerID])?

    // MARK: - Configuration
    /// How often to broadcast location (seconds)
    private let broadcastInterval: TimeInterval = 30

    /// How old a location can be before considered stale (seconds)
    private let stalenessThreshold: TimeInterval = 120

    /// Custom packet type for location sharing (uses reserved range)
    /// This should be added to the packet type enum in BitchatPacket
    static let locationSharePacketType: UInt8 = 0x20

    // MARK: - Published State
    @Published private(set) var isSharing = false
    @Published private(set) var friendLocations: [Data: FriendLocation] = [:]
    @Published private(set) var lastBroadcastTime: Date?
    @Published private(set) var myLocation: CLLocation?

    // MARK: - Private Properties
    private var locationManager: CLLocationManager?
    private var broadcastTimer: DispatchSourceTimer?
    private var stalenessTimer: DispatchSourceTimer?

    // MARK: - Computed Properties
    var activeFriendLocations: [FriendLocation] {
        friendLocations.values.filter { !$0.isStale }.sorted { $0.nickname < $1.nickname }
    }

    var locatedFriends: [FriendLocation] {
        friendLocations.values.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Lifecycle
    private override init() {
        super.init()
        setupStalenessTimer()
    }

    deinit {
        broadcastTimer?.cancel()
        stalenessTimer?.cancel()
    }

    // MARK: - Public API
    func startSharing() {
        guard !isSharing else { return }
        setupLocationManager()
        locationManager?.startUpdatingLocation()
        startBroadcastTimer()
        isSharing = true
        print("📍 FriendLocationService: Started location sharing")
    }

    func stopSharing() {
        guard isSharing else { return }
        locationManager?.stopUpdatingLocation()
        broadcastTimer?.cancel()
        broadcastTimer = nil
        isSharing = false
        print("📍 FriendLocationService: Stopped location sharing")
    }

    func toggleSharing() {
        if isSharing { stopSharing() } else { startSharing() }
    }

    /// Call this from the packet handler when receiving locationSharePacketType
    func handleLocationPacket(senderNoiseKey: Data, senderNickname: String, payload: Data, aeadKey: SymmetricKey? = nil) {
        // Only process from mutual favorites
        guard FavoritesPersistenceService.shared.favorites[senderNoiseKey]?.isMutual == true else {
            print("📍 Ignoring location from non-mutual favorite")
            return
        }

        let plain: Data
        do {
            if let key = aeadKey {
                plain = try AEAD.decrypt(payload, using: key)
            } else {
                // If no key provided assume payload is plaintext (legacy)
                plain = payload
            }
        } catch {
            print("📍 Failed to decrypt location payload: \(error)")
            return
        }

        guard let location = LocationSharePayload.fromData(plain) else {
            print("📍 Failed to decode location payload")
            return
        }

        let friendLocation = FriendLocation(
            id: senderNoiseKey,
            nickname: senderNickname,
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            accuracy: location.accuracy,
            timestamp: Date(timeIntervalSince1970: Double(location.timestamp) / 1000.0),
            isStale: false
        )

        friendLocations[senderNoiseKey] = friendLocation
        print("📍 Updated location for \(senderNickname)")
    }

    func clearLocations() { friendLocations.removeAll() }

    // MARK: - Private Methods
    private func setupLocationManager() {
        guard locationManager == nil else { return }
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.distanceFilter = 10
        locationManager?.allowsBackgroundLocationUpdates = false
        locationManager?.requestWhenInUseAuthorization()
    }

    private func startBroadcastTimer() {
        broadcastTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: broadcastInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.broadcastLocation() }
        }
        broadcastTimer = timer
        timer.resume()
    }

    private func broadcastLocation() {
        guard let location = myLocation else {
            print("📍 broadcastLocation: no GPS fix yet, skipping")
            return
        }
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let acc = location.horizontalAccuracy
        let ts = Int(location.timestamp.timeIntervalSince1970)
        let content = "\(Self.locationMarker)\(lat),\(lng),\(acc),\(ts)"
        switch ShareMode.current {
        case .broadcast:
            guard let broadcaster else {
                print("📍 No broadcaster wired up — location not sent")
                return
            }
            broadcaster(content)
        case .encrypted:
            // No plaintext fallback: with no recipients, nothing is sent.
            let recipients = encryptedRecipients?() ?? []
            guard let encryptedBroadcaster, !recipients.isEmpty else { return }
            encryptedBroadcaster(content, recipients)
        }
        lastBroadcastTime = Date()
    }

    /// Called by `ChatViewModel.didReceiveMessage` when an incoming BLE-mesh
    /// chat-channel message starts with our location marker. We parse the
    /// suffix and update the friend's location entry — no AEAD because the
    /// payload contains only coordinates + accuracy + timestamp.
    func ingestLocationMessage(content: String, senderNoiseKey: Data?, senderNickname: String) {
        guard content.hasPrefix(Self.locationMarker) else { return }
        let body = content.dropFirst(Self.locationMarker.count)
        let parts = body.split(separator: ",")
        guard parts.count >= 4,
              let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              let acc = Double(parts[2]),
              let ts  = TimeInterval(parts[3]) else {
            print("📍 Malformed location packet from \(senderNickname): \(body)")
            return
        }
        // Use a deterministic id even when we don't yet have a noise key
        // (e.g., peer is observed once but not paired into favorites yet).
        let id = senderNoiseKey ?? Data(senderNickname.utf8)
        let fixTime = Date(timeIntervalSince1970: ts)
        // Upstream gossip sync (2026-09 merge) replays up to 6h of public mesh
        // messages to peers that reconnect, so old location packets can arrive
        // after newer ones. Never let an older fix overwrite a newer one.
        if let existing = friendLocations[id], existing.timestamp >= fixTime {
            return
        }
        let friend = FriendLocation(
            id: id,
            nickname: senderNickname,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            accuracy: acc,
            timestamp: fixTime,
            isStale: Date().timeIntervalSince(fixTime) > stalenessThreshold
        )
        friendLocations[id] = friend
    }

    private func setupStalenessTimer() {
        stalenessTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.updateStaleness() }
        }
        stalenessTimer = timer
        timer.resume()
    }

    private func updateStaleness() {
        let now = Date()
        var updated = false
        for (key, location) in friendLocations {
            let age = now.timeIntervalSince(location.timestamp)
            let shouldBeStale = age > stalenessThreshold
            if location.isStale != shouldBeStale {
                friendLocations[key] = FriendLocation(id: location.id, nickname: location.nickname, coordinate: location.coordinate, accuracy: location.accuracy, timestamp: location.timestamp, isStale: shouldBeStale)
                updated = true
            }
        }
        if updated { objectWillChange.send() }
    }
}

// MARK: - CLLocationManagerDelegate
extension FriendLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.myLocation = location }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: if self.isSharing { manager.startUpdatingLocation() }
            case .denied, .restricted: self.stopSharing()
            default: break
            }
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let friendLocationUpdated = Notification.Name("friendLocationUpdated")
}