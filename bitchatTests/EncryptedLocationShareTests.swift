//
// EncryptedLocationShareTests.swift
// bitchatTests
//
// Encrypted friend location (festy#12 / fest-mesh-android#89).
//

import Testing
import Foundation
@testable import bitchat

struct EncryptedLocationShareTests {

    @Test
    func locationShare_wireValueMatchesAndroid() {
        // Pinned cross-platform: fest-mesh-android NoisePayloadType.LOCATION_SHARE = 0x30.
        #expect(NoisePayloadType.locationShare.rawValue == 0x30)
        #expect(NoisePayloadType(rawValue: 0x30) == .locationShare)
    }

    @Test
    func locationSharePayload_roundTripsMarkerCSV() throws {
        let content = "\(FriendLocationService.locationMarker)34.13616,-118.12675,5.0,1790000000"
        let encoded = NoisePayload(type: .locationShare, data: Data(content.utf8)).encode()
        #expect(encoded.first == 0x30)
        let decoded = try #require(NoisePayload.decode(encoded))
        #expect(decoded.type == .locationShare)
        #expect(String(data: decoded.data, encoding: .utf8) == content)
    }

    @Test
    func shareMode_defaultsToBroadcast() {
        let defaults = UserDefaults.standard
        let key = FriendLocationService.ShareMode.storageKey
        let saved = defaults.string(forKey: key)
        defaults.removeObject(forKey: key)
        defer { defaults.set(saved, forKey: key) }
        #expect(FriendLocationService.ShareMode.current == .broadcast)
    }
}
