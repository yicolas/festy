import Foundation
import SwiftUI
import CoreLocation

// MARK: - Trip Theme

enum TripTheme {
    static let background = Color.white
    static let primaryText = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let secondaryText = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let accent = Color(red: 0.95, green: 0.45, blue: 0.1)
    static let accentSoft = accent.opacity(0.12)
}

// MARK: - Trip Data Models

struct TripData: Codable {
    let trip: TripInfo
    let tabs: [TripTab]?
    let channels: [TripChannel]
    let days: [TripDay]
    let infoSections: [TripInfoSection]?
    let mapConfig: TripMapConfig?

    var configuredTabs: [TripTab] {
        tabs ?? TripTab.defaultTabs
    }

    /// Compatibility for legacy festival naming in a few untouched call sites.
    var festival: TripInfo { trip }
}

struct TripInfo: Codable {
    let id: String
    let name: String
    let subtitle: String?
    let location: String
    let dates: TripDates
    let timezone: String?

    var timezoneIdentifier: String {
        timezone ?? "America/Los_Angeles"
    }
}

struct TripDates: Codable {
    let start: String
    let end: String
}

struct TripTab: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let type: TabType

    enum TabType: String, Codable {
        case schedule
        case channels
        case map
        case chat
        case info
        case friends
        case groups
        case custom
    }

    static var defaultTabs: [TripTab] {
        [
            TripTab(id: "schedule", name: "Schedule", icon: "calendar", type: .schedule),
            TripTab(id: "channels", name: "Channels", icon: "number", type: .channels),
            TripTab(id: "map", name: "Map", icon: "map", type: .map),
            TripTab(id: "chat", name: "Chat", icon: "bubble.left.and.bubble.right", type: .chat),
            TripTab(id: "info", name: "Info", icon: "info.circle", type: .info)
        ]
    }
}

struct TripDay: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let date: String
    let startTime: String?
    let items: [TripItem]
    let routeURL: String?
}

struct TripItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let location: TripLocation?
    let arrive: String?
    let duration: String?
    let leave: String?
    let driveTime: String?
    let bathroom: Bool?
    let food: Bool?
    let presenters: [String]?
    let notes: String?

    var timeRangeText: String {
        switch (arrive, leave) {
        case let (arrive?, leave?):
            return "\(arrive) - \(leave)"
        case let (arrive?, nil):
            return "Arrive \(arrive)"
        default:
            return "Time TBD"
        }
    }
}

struct TripLocation: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TripChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String?
}

struct TripInfoSection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let bullets: [String]
}

struct TripMapConfig: Codable, Hashable {
    let centerLatitude: Double?
    let centerLongitude: Double?
    let latitudeDelta: Double?
    let longitudeDelta: Double?
    let routeLinks: [TripRouteLink]?
}

struct TripRouteLink: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
}

// MARK: - Trip Schedule Manager

@MainActor
class TripScheduleManager: ObservableObject {
    static let shared = TripScheduleManager()

    @Published var tripData: TripData?
    @Published var selectedDay: String?
    @Published var isLoaded = false

    /// Compatibility read-only alias for legacy references.
    var festivalData: TripData? { tripData }

    private init() {
        loadSchedule()
    }

    func loadSchedule() {
        let resourceNames = ["FestivalSchedule", "TripSchedule"]

        for name in resourceNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(TripData.self, from: data) {
                tripData = decoded
                selectedDay = decoded.days.first?.date
                isLoaded = true
                return
            }
        }

        print("Failed to load trip schedule")
    }

    var timezone: String {
        tripData?.trip.timezoneIdentifier ?? "America/Los_Angeles"
    }

    var tabs: [TripTab] {
        tripData?.configuredTabs ?? TripTab.defaultTabs
    }

    var days: [String] {
        guard let tripData else { return [] }
        return tripData.days
            .map(\.date)
            .sorted()
    }

    var channels: [TripChannel] {
        tripData?.channels ?? []
    }

    var infoSections: [TripInfoSection] {
        tripData?.infoSections ?? []
    }

    var mapConfig: TripMapConfig? {
        tripData?.mapConfig
    }

    var allLocations: [TripLocation] {
        guard let tripData else { return [] }

        let all = tripData.days
            .flatMap { $0.items }
            .compactMap { $0.location }

        var seen = Set<String>()
        return all.filter { location in
            if seen.contains(location.id) { return false }
            seen.insert(location.id)
            return true
        }
    }

    func dayData(for day: String) -> TripDay? {
        tripData?.days.first(where: { $0.date == day })
    }

    func items(for day: String) -> [TripItem] {
        dayData(for: day)?.items ?? []
    }

    func formatDayForDisplay(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return day }

        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Compatibility Typealiases (keeps older references buildable)

typealias FestivalData = TripData
typealias FestivalInfo = TripInfo
typealias FestivalTab = TripTab
typealias FestivalScheduleManager = TripScheduleManager

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
