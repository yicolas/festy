//
// FriendLocationService.swift
// bitchat
//
// Location sharing service for mutual favorites on trips
//

#if os(iOS)
import BitFoundation // PeerID (sending side)
#endif
import Foundation
import CoreLocation
import Combine

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

/// Manages location sharing with mutual favorites
@MainActor
class FriendLocationService: NSObject, ObservableObject {
    static let shared = FriendLocationService()

    /// Wire-level marker prefix for location packets sent as chat-channel
    /// messages. The leading control char ensures no collision with real text.
    static let locationMarker = "\u{1}GE136C-LOC\u{1}"

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

        static var current: ShareMode {
            UserDefaults.standard.string(forKey: storageKey).flatMap(ShareMode.init(rawValue:)) ?? .broadcast
        }

        #if os(iOS)
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
        #endif
    }

    /// How old a location can be before considered stale (seconds)
    private let stalenessThreshold: TimeInterval = 120

    @Published private(set) var friendLocations: [Data: FriendLocation] = [:]
    private var stalenessTimer: DispatchSourceTimer?

    // MARK: - Sending (iOS only: the macOS build has no trip map to start it)
    #if os(iOS)
    /// Closure invoked when this device wants to broadcast its location.
    /// `ChatViewModel` sets this in init so we can fan the encoded string out
    /// over the existing BLE-mesh chat transport.
    var broadcaster: ((String) -> Void)?

    /// Sends the marker+CSV string encrypted to each recipient (`.encrypted`
    /// mode). Wired by ChatViewModel to `Transport.sendEncryptedLocationShare`.
    var encryptedBroadcaster: ((String, [PeerID]) -> Void)?

    /// Recipients for `.encrypted` mode: connected mutual favorites. Wired by
    /// ChatViewModel.
    var encryptedRecipients: (() -> [PeerID])?

    /// How often to broadcast location (seconds)
    private let broadcastInterval: TimeInterval = 30

    @Published private(set) var isSharing = false
    @Published private(set) var lastBroadcastTime: Date?
    @Published private(set) var myLocation: CLLocation?

    private var locationManager: CLLocationManager?
    private var broadcastTimer: DispatchSourceTimer?

    // MARK: - Computed Properties
    var activeFriendLocations: [FriendLocation] {
        friendLocations.values.filter { !$0.isStale }.sorted { $0.nickname < $1.nickname }
    }

    var locatedFriends: [FriendLocation] {
        friendLocations.values.sorted { $0.timestamp > $1.timestamp }
    }

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
    #endif

    // MARK: - Lifecycle
    private override init() {
        super.init()
        setupStalenessTimer()
    }

    deinit {
        #if os(iOS)
        broadcastTimer?.cancel()
        #endif
        stalenessTimer?.cancel()
    }

    // MARK: - Receiving

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
#if os(iOS)
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
#endif
