//
// TripConfigTests.swift
// bitchatTests
//
// Trip configuration: everything trip-specific comes from TripSchedule.json,
// and storage keys / Nostr tags derive from the trip namespace.
//

import Testing
import Foundation
@testable import bitchat

struct TripConfigTests {

    private static let minimalTripJSON = """
    {
      "trip": {
        "id": "test-trip-2026",
        "name": "Test Trip",
        "location": "Somewhere",
        "dates": { "start": "2026-10-16", "end": "2026-10-18" }
      },
      "channels": [],
      "days": []
    }
    """

    private func decode(_ json: String) throws -> TripData {
        try JSONDecoder().decode(TripData.self, from: Data(json.utf8))
    }

    @Test
    func bundledTrip_decodes() throws {
        let trip = try #require(TripData.bundled)
        #expect(!trip.trip.name.isEmpty)
        #expect(!trip.days.isEmpty)
    }

    @Test
    func minimalTrip_withoutOptionalSections_decodes() throws {
        let trip = try decode(Self.minimalTripJSON)
        #expect(trip.infoLinks == nil)
        #expect(trip.safety == nil)
        #expect(trip.seedMessages == nil)
        #expect(trip.trip.storageNamespace == "test-trip-2026")
        #expect(trip.trip.displayShortName == "Test Trip")
    }

    @Test
    func namespace_overridesID() throws {
        let json = Self.minimalTripJSON.replacingOccurrences(
            of: "\"id\": \"test-trip-2026\",",
            with: "\"id\": \"test-trip-2026\", \"namespace\": \"tt26\",")
        let trip = try decode(json)
        #expect(trip.trip.storageNamespace == "tt26")
    }

    @Test
    func derivedKeysAndTags_useNamespace() {
        let ns = TripNamespace.value
        #expect(ns == TripData.bundled?.trip.storageNamespace)
        #expect(TripNamespace.key("hiddenDayIndices") == "\(ns).hiddenDayIndices")
        #expect(TripNamespace.file("trip-notes.json") == "\(ns)-trip-notes.json")
        #expect(NostrProtocol.selfieDTag == "\(ns).selfie")
        #expect(NostrProtocol.tripNoteKTag == "\(ns).notes")
        #expect(TripNamespace.tripNoteDTagPrefix == "\(ns).note.")
    }

    @Test
    func seedMessages_useTripTimezone() {
        let seeds = TripSeedMessages(version: 1, messages: [
            TripSeedMessage(id: "seed-1", time: "2026-05-29 18:30", text: "Friday dinner #meals"),
            TripSeedMessage(id: "bad", time: "not a time", text: "skipped")
        ])
        let messages = seeds.bitchatMessages(timezoneIdentifier: "America/Los_Angeles")
        #expect(messages.map(\.id) == ["seed-1"])
        // 18:30 PDT (UTC-7) = 01:30 UTC next day.
        let expected = ISO8601DateFormatter().date(from: "2026-05-30T01:30:00Z")
        #expect(messages.first?.timestamp == expected)
        #expect(messages.first?.sender == "system")
    }

    @Test
    func bundledTrip_contentIsWellFormed() throws {
        let trip = try #require(TripData.bundled)
        if let seeds = trip.seedMessages {
            let messages = seeds.bitchatMessages(timezoneIdentifier: trip.trip.timezoneIdentifier)
            #expect(messages.count == seeds.messages.count, "every seed time must parse as yyyy-MM-dd HH:mm")
            #expect(Set(seeds.messages.map(\.id)).count == seeds.messages.count)
        }
        if let links = trip.infoLinks {
            #expect(Set(links.map(\.id)).count == links.count)
        }
        // rangeText falls back to the raw strings only when they don't parse.
        let dates = trip.trip.dates
        #expect(trip.trip.dateRangeText != "\(dates.start) – \(dates.end)", "trip dates must be yyyy-MM-dd")
    }

    // MARK: Trip switching

    private static func bundledTripFiles() -> [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("trip-") }
    }

    @Test
    func everyBundledTripFile_decodes() throws {
        let files = Self.bundledTripFiles()
        #expect(files.count >= 2, "expected the GE136C trip and the October placeholder")
        for url in files {
            do {
                _ = try JSONDecoder().decode(TripData.self, from: Data(contentsOf: url))
            } catch {
                Issue.record("\(url.lastPathComponent) failed to decode: \(error)")
            }
        }
    }

    @Test
    func activeTrip_hasNoPlaceholders() throws {
        let url = try #require(Bundle.main.url(forResource: TripData.activeResourceName, withExtension: "json"))
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("FILL_IN"), "active trip \(TripData.activeResourceName) still has FILL_IN values")
    }
}
