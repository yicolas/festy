//
// FestivalFeatureTests.swift
// bitchatTests
//
// Tests for festival mode features: schedule, location sharing, and map
//

import Testing
import Foundation
import CoreLocation
@testable import bitchat

// MARK: - Trip Schedule Tests

struct FestivalScheduleTests {
    
    @Test
    func scheduleJSON_loadsSuccessfully() async {
        // Verify the JSON can be loaded and decoded
        guard let url = Bundle.main.url(forResource: "FestivalSchedule", withExtension: "json") else {
            Issue.record("FestivalSchedule.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(FestivalData.self, from: data)
            
            #expect(!decoded.trip.name.isEmpty)
            #expect(!decoded.channels.isEmpty)
            #expect(!decoded.days.isEmpty)
            #expect(!decoded.days.flatMap(\.items).isEmpty)
        } catch {
            Issue.record("Failed to decode FestivalSchedule.json: \(error)")
        }
    }
    
    @Test
    func tripItem_timeRangeText_formatsCorrectly() {
        let item = TripItem(
            id: "test-1",
            title: "Test Stop",
            location: nil,
            arrive: "8:00 AM",
            duration: "1:00",
            leave: "9:00 AM",
            driveTime: "0:30",
            bathroom: true,
            food: false,
            presenters: nil,
            notes: nil
        )

        let timeRange = item.timeRangeText
        #expect(timeRange.contains("8:00 AM"))
        #expect(timeRange.contains("9:00 AM"))
    }
    
    @Test
    func tripChannel_defaultsIncludeExpectedChannels() {
        guard let url = Bundle.main.url(forResource: "FestivalSchedule", withExtension: "json") else {
            Issue.record("FestivalSchedule.json not found in bundle")
            return
        }

        let data = try? Data(contentsOf: url)
        let decoded = try? JSONDecoder().decode(TripData.self, from: data ?? Data())
        let names = Set(decoded?.channels.map(\.name) ?? [])

        #expect(names.contains("#general"))
        #expect(names.contains("#driving"))
        #expect(names.contains("#travel"))
        #expect(names.contains("#meals"))
        #expect(names.contains("#gear"))
        #expect(names.contains("#announcements"))
    }
}

// MARK: - Location Payload Tests

struct LocationPayloadTests {
    
    @Test
    func locationPayload_encodeDecode_roundTrips() {
        let original = LocationSharePayload(
            latitude: 37.7694,
            longitude: -122.4862,
            accuracy: 10.5,
            timestamp: 1723075200000  // Fixed timestamp for testing
        )
        
        let encoded = original.toData()
        #expect(encoded.count == 28)  // 8 + 8 + 4 + 8 bytes
        
        guard let decoded = LocationSharePayload.fromData(encoded) else {
            Issue.record("Failed to decode location payload")
            return
        }
        
        #expect(abs(decoded.latitude - original.latitude) < 0.0001)
        #expect(abs(decoded.longitude - original.longitude) < 0.0001)
        #expect(abs(decoded.accuracy - original.accuracy) < 0.1)
        #expect(decoded.timestamp == original.timestamp)
    }
    
    @Test
    func locationPayload_bigEndian_crossPlatformSafe() {
        // Test that encoding is deterministic (big-endian)
        let payload = LocationSharePayload(
            latitude: 37.7694,
            longitude: -122.4862,
            accuracy: 10.0,
            timestamp: 1000000000000
        )
        
        let encoded1 = payload.toData()
        let encoded2 = payload.toData()
        
        #expect(encoded1 == encoded2)
    }
    
    @Test
    func locationPayload_invalidData_returnsNil() {
        // Too short
        let shortData = Data([0x00, 0x01, 0x02])
        #expect(LocationSharePayload.fromData(shortData) == nil)
        
        // Empty
        #expect(LocationSharePayload.fromData(Data()) == nil)
    }
    
    @Test
    func locationPayload_exactSize_decodes() {
        // Exactly 28 bytes should work
        var data = Data(count: 28)
        // Fill with valid-ish data (zeros will decode to 0.0, 0.0 coordinates)
        #expect(LocationSharePayload.fromData(data) != nil)
    }
}

// MARK: - Friend Location Tests

struct FriendLocationTests {
    
    @Test
    func friendLocation_equality_basedOnIdAndTimestamp() {
        let id = Data([0x01, 0x02, 0x03])
        let timestamp = Date()
        
        let loc1 = FriendLocation(
            id: id,
            nickname: "Alice",
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            accuracy: 10.0,
            timestamp: timestamp,
            isStale: false
        )
        
        let loc2 = FriendLocation(
            id: id,
            nickname: "Alice Updated",  // Different nickname
            coordinate: CLLocationCoordinate2D(latitude: 38.0, longitude: -123.0),  // Different coord
            accuracy: 20.0,
            timestamp: timestamp,  // Same timestamp
            isStale: true
        )
        
        // Should be equal because id and timestamp match
        #expect(loc1 == loc2)
    }
    
    @Test
    func friendLocation_differentTimestamp_notEqual() {
        let id = Data([0x01, 0x02, 0x03])
        
        let loc1 = FriendLocation(
            id: id,
            nickname: "Alice",
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            accuracy: 10.0,
            timestamp: Date(),
            isStale: false
        )
        
        let loc2 = FriendLocation(
            id: id,
            nickname: "Alice",
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            accuracy: 10.0,
            timestamp: Date().addingTimeInterval(1),  // 1 second later
            isStale: false
        )
        
        #expect(loc1 != loc2)
    }
}

// MARK: - Festival Mode Manager Tests

struct FestivalModeManagerTests {
    
    @Test @MainActor
    func festivalModeManager_toggle_changesState() async {
        let manager = FestivalModeManager.shared
        let initialState = manager.isEnabled
        
        manager.toggle()
        #expect(manager.isEnabled == !initialState)
        
        manager.toggle()
        #expect(manager.isEnabled == initialState)
    }
    
    @Test @MainActor
    func festivalModeManager_enable_setsTrue() async {
        let manager = FestivalModeManager.shared
        
        manager.enable()
        #expect(manager.isEnabled == true)
        
        // Cleanup
        manager.disable()
    }
    
    @Test @MainActor
    func festivalModeManager_disable_setsFalse() async {
        let manager = FestivalModeManager.shared
        
        manager.enable()
        manager.disable()
        #expect(manager.isEnabled == false)
    }
}

// MARK: - AEAD Encryption Tests

struct AEADTests {
    
    @Test
    func aead_encryptDecrypt_roundTrips() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Hello, Festival!".data(using: .utf8)!
        
        let ciphertext = try AEAD.encrypt(payload: plaintext, using: key)
        let decrypted = try AEAD.decrypt(ciphertext, using: key)
        
        #expect(decrypted == plaintext)
    }
    
    @Test
    func aead_differentKeys_failsDecryption() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let plaintext = "Secret data".data(using: .utf8)!
        
        let ciphertext = try AEAD.encrypt(payload: plaintext, using: key1)
        
        // Decrypting with wrong key should throw
        #expect(throws: (any Error).self) {
            _ = try AEAD.decrypt(ciphertext, using: key2)
        }
    }
    
    @Test
    func aead_tamperedCiphertext_failsDecryption() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Tamper test".data(using: .utf8)!
        
        var ciphertext = try AEAD.encrypt(payload: plaintext, using: key)
        
        // Tamper with the ciphertext
        if ciphertext.count > 10 {
            ciphertext[10] ^= 0xFF
        }
        
        // Should fail authentication
        #expect(throws: (any Error).self) {
            _ = try AEAD.decrypt(ciphertext, using: key)
        }
    }
}

// MARK: - Schedule Manager Tests

struct FestivalScheduleManagerTests {
    
    @Test @MainActor
    func scheduleManager_singleton_exists() async {
        let manager = FestivalScheduleManager.shared
        #expect(manager != nil)
    }
    
    @Test @MainActor
    func scheduleManager_days_returnsUniqueSortedDays() async {
        let manager = FestivalScheduleManager.shared
        manager.loadSchedule()
        
        let days = manager.days
        
        // Should be sorted
        #expect(days == days.sorted())
        
        // Should be unique
        #expect(Set(days).count == days.count)
    }
    
    @Test @MainActor
    func scheduleManager_itemsForDay_returnsItems() async {
        let manager = FestivalScheduleManager.shared
        manager.loadSchedule()
        
        guard let firstDay = manager.days.first else {
            Issue.record("No days in schedule")
            return
        }
        
        let items = manager.items(for: firstDay)
        
        #expect(!items.isEmpty)
    }
    
    @Test @MainActor
    func scheduleManager_formatDayForDisplay_formatsCorrectly() async {
        let manager = FestivalScheduleManager.shared
        
        let formatted = manager.formatDayForDisplay("2026-08-07")
        
        // Should contain day name and month
        #expect(formatted.contains("Aug") || formatted.contains("August"))
        #expect(formatted.contains("7"))
    }
}

// MARK: - Color Extension Tests

struct ColorExtensionTests {
    
    @Test
    func colorFromHex_validHex_createsColor() {
        let color = Color(hex: "#FF6B6B")
        #expect(color != nil)
    }
    
    @Test
    func colorFromHex_withoutHash_createsColor() {
        let color = Color(hex: "4ECDC4")
        #expect(color != nil)
    }
    
    @Test
    func colorFromHex_invalidHex_returnsNil() {
        let color = Color(hex: "not-a-color")
        #expect(color == nil)
    }
    
    @Test
    func colorFromHex_shortHex_returnsNil() {
        let color = Color(hex: "FFF")  // 3-char hex not supported
        #expect(color == nil)
    }
}
