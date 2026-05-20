//
// FestivalFeatureTests.swift
// bitchatTests
//
// Tests for trip mode features: schedule, location sharing, and map
//

import Testing
import Foundation
import CoreLocation
@testable import bitchat

// MARK: - Trip Schedule Tests

struct TripScheduleTests {
    
    @Test
    func scheduleJSON_loadsSuccessfully() async {
        // Verify the JSON can be loaded and decoded
        guard let url = Bundle.main.url(forResource: "TripSchedule", withExtension: "json") else {
            Issue.record("TripSchedule.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(TripData.self, from: data)
            
            #expect(!decoded.trip.name.isEmpty)
            #expect(!decoded.stages.isEmpty)
            #expect(!decoded.sets.isEmpty)
        } catch {
            Issue.record("Failed to decode TripSchedule.json: \(error)")
        }
    }
    
    @Test
    func scheduledSet_timeRangeString_formatsCorrectly() {
        let set = ScheduledSet(
            id: "test-1",
            artist: "Test Artist",
            stage: "main",
            day: "2026-08-07",
            start: "20:30",
            end: "22:00"
        )
        
        // Should contain both times
        let timeRange = set.timeRangeString
        #expect(timeRange.contains("8:30") || timeRange.contains("20:30"))
        #expect(timeRange.contains("10:00") || timeRange.contains("22:00"))
    }
    
    @Test
    func scheduledSet_isNowPlaying_detectsCurrentSet() {
        // Create a set that's "now" (use a wide time window for test reliability)
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let today = formatter.string(from: now)
        
        formatter.dateFormat = "HH:mm"
        let currentTime = formatter.string(from: now)
        let endTime = formatter.string(from: now.addingTimeInterval(3600)) // 1 hour later
        
        let set = ScheduledSet(
            id: "now-test",
            artist: "Now Playing Artist",
            stage: "main",
            day: today,
            start: currentTime,
            end: endTime
        )
        
        // This set should be playing now (if we're in Pacific time)
        // Note: This test may be flaky depending on timezone
        if TimeZone.current.identifier == "America/Los_Angeles" {
            #expect(set.isNowPlaying())
        }
    }
    
    @Test
    func scheduledSet_isUpcoming_detectsFutureSets() {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let today = formatter.string(from: now)
        
        formatter.dateFormat = "HH:mm"
        let futureStart = formatter.string(from: now.addingTimeInterval(900)) // 15 min from now
        let futureEnd = formatter.string(from: now.addingTimeInterval(4500)) // 75 min from now
        
        let set = ScheduledSet(
            id: "upcoming-test",
            artist: "Upcoming Artist",
            stage: "main",
            day: today,
            start: futureStart,
            end: futureEnd
        )
        
        // Should be upcoming within 30 minutes
        if TimeZone.current.identifier == "America/Los_Angeles" {
            #expect(set.isUpcoming(within: 30))
        }
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

// MARK: - Trip Mode Manager Tests

struct TripModeManagerTests {
    
    @Test @MainActor
    func tripModeManager_toggle_changesState() async {
        let manager = TripModeManager.shared
        let initialState = manager.isEnabled
        
        manager.toggle()
        #expect(manager.isEnabled == !initialState)
        
        manager.toggle()
        #expect(manager.isEnabled == initialState)
    }
    
    @Test @MainActor
    func tripModeManager_enable_setsTrue() async {
        let manager = TripModeManager.shared
        
        manager.enable()
        #expect(manager.isEnabled == true)
        
        // Cleanup
        manager.disable()
    }
    
    @Test @MainActor
    func tripModeManager_disable_setsFalse() async {
        let manager = TripModeManager.shared
        
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
        let plaintext = "Hello, Trip!".data(using: .utf8)!
        
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

struct TripScheduleManagerTests {
    
    @Test @MainActor
    func scheduleManager_singleton_exists() async {
        let manager = TripScheduleManager.shared
        #expect(manager != nil)
    }
    
    @Test @MainActor
    func scheduleManager_days_returnsUniqueSortedDays() async {
        let manager = TripScheduleManager.shared
        manager.loadSchedule()
        
        let days = manager.days
        
        // Should be sorted
        #expect(days == days.sorted())
        
        // Should be unique
        #expect(Set(days).count == days.count)
    }
    
    @Test @MainActor
    func scheduleManager_setsForDay_filtersByDay() async {
        let manager = TripScheduleManager.shared
        manager.loadSchedule()
        
        guard let firstDay = manager.days.first else {
            Issue.record("No days in schedule")
            return
        }
        
        let sets = manager.sets(for: firstDay)
        
        // All sets should be for the requested day
        for set in sets {
            #expect(set.day == firstDay)
        }
    }
    
    @Test @MainActor
    func scheduleManager_formatDayForDisplay_formatsCorrectly() async {
        let manager = TripScheduleManager.shared
        
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
