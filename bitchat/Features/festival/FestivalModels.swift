//
// FestivalModels.swift
// bitchat
//
// Trip schedule data models
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Trip Data Models

struct TripData: Codable {
    let trip: TripInfo
    let tabs: [TripTab]?
    let stages: [Stage]
    let sets: [ScheduledSet]
    let customChannels: [CustomChannel]?
    let mapBounds: MapBounds?
    let pointsOfInterest: [PointOfInterest]?
    
    /// Get configured tabs, or default tabs if none specified
    var configuredTabs: [TripTab] {
        tabs ?? TripTab.defaultTabs
    }
}

struct TripInfo: Codable {
    let name: String
    let location: String
    let dates: TripDates
    let gatesOpen: String
    let musicStart: String
    let musicEnd: String
    let timezone: String?
    
    var timezoneIdentifier: String {
        timezone ?? "America/Los_Angeles"
    }
}

struct TripDates: Codable {
    let start: String
    let end: String
}

// MARK: - Configurable Tab Model

/// Tab configuration from JSON - allows trips to customize which tabs appear
struct TripTab: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let type: TabType
    
    enum TabType: String, Codable {
        case schedule   // Show TripScheduleView
        case channels   // Show TripChannelsView
        case chat       // Show main chat ContentView
        case map        // Show TripMapView
        case info       // Show TripInfoView
        case friends    // Show FriendMapView (location sharing)
        case groups     // Show TripGroupsView (user-created groups)
        case custom     // Future: custom webview or embedded content
    }
    
    /// Default tabs if none specified in JSON
    static var defaultTabs: [TripTab] {
        [
            TripTab(id: "schedule", name: "Schedule", icon: "calendar", type: .schedule),
            TripTab(id: "channels", name: "Channels", icon: "antenna.radiowaves.left.and.right", type: .channels),
            TripTab(id: "groups", name: "Groups", icon: "person.3", type: .groups),
            TripTab(id: "chat", name: "Mesh Chat", icon: "bubble.left.and.bubble.right", type: .chat),
            TripTab(id: "info", name: "Info", icon: "info.circle", type: .info)
        ]
    }
}

struct Stage: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let color: String
    let geohash: String?
    let latitude: Double?
    let longitude: Double?
    
    var swiftUIColor: Color {
        Color(hex: color) ?? .gray
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Channel name for this stage (e.g., "#lands-end")
    var channelName: String {
        "#\(id)"
    }
}

struct CustomChannel: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String
    
    var swiftUIColor: Color {
        Color(hex: color) ?? .gray
    }
}

struct MapBounds: Codable {
    let northEast: Coordinate
    let southWest: Coordinate
    
    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
        
        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

struct PointOfInterest: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let latitude: Double
    let longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ScheduledSet: Codable, Identifiable {
    let id: String
    let artist: String
    let stage: String
    let day: String
    let start: String
    let end: String
    let genre: String?
    
    /// Parse start time as Date for the given day
    func startDate(timezone: String = "America/Los_Angeles") -> Date? {
        parseDateTime(day: day, time: start, timezone: timezone)
    }
    
    /// Parse end time as Date for the given day
    func endDate(timezone: String = "America/Los_Angeles") -> Date? {
        parseDateTime(day: day, time: end, timezone: timezone)
    }
    
    /// Check if this set is currently playing
    func isNowPlaying(currentDate: Date = Date(), timezone: String = "America/Los_Angeles") -> Bool {
        guard let start = startDate(timezone: timezone), 
              let end = endDate(timezone: timezone) else { return false }
        return currentDate >= start && currentDate < end
    }
    
    /// Check if this set is coming up within the next N minutes
    func isUpcoming(within minutes: Int = 30, currentDate: Date = Date(), timezone: String = "America/Los_Angeles") -> Bool {
        guard let start = startDate(timezone: timezone) else { return false }
        let threshold = currentDate.addingTimeInterval(TimeInterval(minutes * 60))
        return start > currentDate && start <= threshold
    }
    
    /// Formatted time range string (e.g., "8:30 PM - 10:00 PM")
    var timeRangeString: String {
        guard let startDate = startDate(), let endDate = endDate() else {
            return "\(start) - \(end)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
    
    private func parseDateTime(day: String, time: String, timezone: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: timezone)
        return formatter.date(from: "\(day) \(time)")
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        guard hexSanitized.count == 6 else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Schedule Manager

@MainActor
class TripScheduleManager: ObservableObject {
    static let shared = TripScheduleManager()
    
    @Published var tripData: TripData?
    @Published var selectedDay: String?
    @Published var selectedStage: String?
    @Published var isLoaded = false
    
    private init() {
        loadSchedule()
    }
    
    func loadSchedule() {
        guard let url = Bundle.main.url(forResource: "TripSchedule", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TripData.self, from: data) else {
            print("Failed to load trip schedule")
            return
        }
        
        self.tripData = decoded
        self.selectedDay = decoded.trip.dates.start
        self.isLoaded = true
    }
    
    /// Trip timezone
    var timezone: String {
        tripData?.trip.timezoneIdentifier ?? "America/Los_Angeles"
    }
    
    /// Get configured tabs for this trip
    var tabs: [TripTab] {
        tripData?.configuredTabs ?? TripTab.defaultTabs
    }
    
    /// Get all unique days from the schedule
    var days: [String] {
        guard let data = tripData else { return [] }
        return Array(Set(data.sets.map { $0.day })).sorted()
    }
    
    /// Get sets for a specific day, sorted by start time
    func sets(for day: String) -> [ScheduledSet] {
        guard let data = tripData else { return [] }
        return data.sets
            .filter { $0.day == day }
            .sorted { ($0.startDate(timezone: timezone) ?? .distantPast) < ($1.startDate(timezone: timezone) ?? .distantPast) }
    }
    
    /// Get sets for a specific day and stage
    func sets(for day: String, stage: String) -> [ScheduledSet] {
        sets(for: day).filter { $0.stage == stage }
    }
    
    /// Get the currently playing sets
    var nowPlaying: [ScheduledSet] {
        guard let data = tripData else { return [] }
        let now = Date()
        return data.sets.filter { $0.isNowPlaying(currentDate: now, timezone: timezone) }
    }
    
    /// Get upcoming sets within the next 30 minutes
    var upcomingSoon: [ScheduledSet] {
        guard let data = tripData else { return [] }
        let now = Date()
        return data.sets
            .filter { $0.isUpcoming(within: 30, currentDate: now, timezone: timezone) }
            .sorted { ($0.startDate(timezone: timezone) ?? .distantPast) < ($1.startDate(timezone: timezone) ?? .distantPast) }
    }
    
    /// Get stage by ID
    func stage(for id: String) -> Stage? {
        tripData?.stages.first { $0.id == id }
    }
    
    /// Get custom channels
    var customChannels: [CustomChannel] {
        tripData?.customChannels ?? []
    }
    
    /// Get points of interest
    var pointsOfInterest: [PointOfInterest] {
        tripData?.pointsOfInterest ?? []
    }
    
    /// Get nearest stage to a location
    func nearestStage(to location: CLLocation) -> Stage? {
        tripData?.stages
            .compactMap { stage -> (Stage, CLLocationDistance)? in
                guard let coord = stage.coordinate else { return nil }
                let stageLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                return (stage, location.distance(from: stageLocation))
            }
            .min { $0.1 < $1.1 }?
            .0
    }
    
    /// Format day string for display
    func formatDayForDisplay(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }
        
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}
