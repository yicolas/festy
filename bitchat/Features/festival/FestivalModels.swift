import Foundation
import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Trip Theme

enum TripTheme {
    // Dark-mode-aware. Uses system-resolved colors so trip-mode UI follows
    // either the system color scheme or whatever override the user picked
    // in the appearance menu.
    #if canImport(UIKit)
    static let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })
    static let primaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    })
    static let secondaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.7, alpha: 1)
            : UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
    })
    /// Surface for normal cards — black-ish in dark, white in light.
    static let surface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.05, alpha: 1)
            : UIColor.white
    })
    /// Surface for card headers / banners — dark grey in dark, accent-soft in light.
    static let cardHeaderBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.18, alpha: 1)
            : UIColor(red: 1.00, green: 0.49, blue: 0.08, alpha: 0.12) // accent @ 12%
    })
    /// Channel subheader (centered) — neutral grey in both modes.
    static let subheaderBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.20, alpha: 1)
            : UIColor(white: 0.86, alpha: 1)
    })
    /// Text color that lives on top of `surface`. In dark mode, orange for
    /// brand emphasis on dark cards; in light mode falls back to primary text.
    static let onSurfaceText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.49, blue: 0.08, alpha: 1) // accent
            : UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1) // primary text
    })
    static let stroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1)
            : UIColor(white: 0.85, alpha: 1)
    })
    #else
    static let background = Color.white
    static let primaryText = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let secondaryText = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let surface = Color.white
    static let cardHeaderBackground = Color(red: 1.00, green: 0.49, blue: 0.08).opacity(0.12)
    static let subheaderBackground = Color(white: 0.86)
    static let onSurfaceText = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let stroke = Color.gray.opacity(0.2)
    #endif
    static let accent = Color(red: 1.00, green: 0.49, blue: 0.08) // #FF7E15
    static let accentSoft = accent.opacity(0.12)

    /// Replaces the bitchat-heritage terminal green throughout the chat UI.
    /// Same hue/sat/brightness as the `#channels` button's mesh-mode color.
    static let uiTint = Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
    static let uiTintSoft = uiTint.opacity(0.15)

    /// Distinct color per trip day (cycles past 4). Same hue used for the day
    /// picker pill and the route polyline on the map.
    static func dayColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 1.00, green: 0.49, blue: 0.08),  // Day 1 - orange (GE136C accent)
            Color(red: 0.18, green: 0.55, blue: 0.92),  // Day 2 - blue
            Color(red: 0.29, green: 0.74, blue: 0.20),  // Day 3 - green
            Color(red: 0.72, green: 0.43, blue: 0.88)   // Day 4 - purple
        ]
        return palette[((index % palette.count) + palette.count) % palette.count]
    }

    #if canImport(UIKit)
    static func dayUIColor(_ index: Int) -> UIColor {
        let palette: [UIColor] = [
            UIColor(red: 1.00, green: 0.49, blue: 0.08, alpha: 1.0),
            UIColor(red: 0.18, green: 0.55, blue: 0.92, alpha: 1.0),
            UIColor(red: 0.29, green: 0.74, blue: 0.20, alpha: 1.0),
            UIColor(red: 0.72, green: 0.43, blue: 0.88, alpha: 1.0)
        ]
        return palette[((index % palette.count) + palette.count) % palette.count]
    }
    #endif
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

    /// Coordinates of every item in order, dropping items without a location.
    var routeCoordinates: [CLLocationCoordinate2D] {
        items.compactMap { $0.location?.coordinate }
    }

    /// Organic Maps URL for the day's start → end (driving). OM URL scheme
    /// doesn't support multi-waypoint routes, so intermediate stops are dropped.
    var organicMapsURL: URL? {
        let coords = routeCoordinates
        guard let start = coords.first, let end = coords.last, coords.count >= 2 else { return nil }
        let saddr = items.first?.location?.name ?? "Start"
        let daddr = items.last?.location?.name ?? "End"
        let urlStr = "om://route?sll=\(start.latitude),\(start.longitude)" +
                     "&saddr=\(saddr.urlEscaped)" +
                     "&dll=\(end.latitude),\(end.longitude)" +
                     "&daddr=\(daddr.urlEscaped)" +
                     "&type=vehicle"
        return URL(string: urlStr)
    }

    var googleMapsURL: URL? {
        guard let routeURL else { return nil }
        return URL(string: routeURL)
    }
}

private extension String {
    var urlEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
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
// Auto-generated from geojson tracks. Pairs are (latitude, longitude).
enum TripRouteGeometry {
    static let kingsCanyonLoop: [(Double, Double)] = [
        (36.796650, -118.584614),
        (36.796502, -118.584395),
        (36.796489, -118.583422),
        (36.796261, -118.582928),
        (36.795926, -118.582601),
        (36.795454, -118.582097),
        (36.795063, -118.581973),
        (36.794805, -118.581464),
        (36.794512, -118.581021),
        (36.794511, -118.581021),
        (36.794507, -118.580700),
        (36.794563, -118.579628),
        (36.794912, -118.578954),
        (36.795093, -118.578853),
        (36.795373, -118.578048),
        (36.795409, -118.577712),
        (36.795448, -118.577649),
        (36.795501, -118.577140),
        (36.795578, -118.576489),
        (36.795568, -118.576245),
        (36.795341, -118.575733),
        (36.795304, -118.575488),
        (36.795244, -118.574760),
        (36.794890, -118.573448),
        (36.794722, -118.573184),
        (36.794680, -118.572909),
        (36.794595, -118.572657),
        (36.794494, -118.572270),
        (36.794110, -118.571690),
        (36.793975, -118.571565),
        (36.793667, -118.571163),
        (36.793345, -118.570729),
        (36.793195, -118.570557),
        (36.792970, -118.570397),
        (36.792694, -118.570025),
        (36.792278, -118.569400),
        (36.792020, -118.568876),
        (36.791792, -118.568241),
        (36.791430, -118.567746),
        (36.791126, -118.567382),
        (36.790687, -118.566762),
        (36.790249, -118.565712),
        (36.790074, -118.565344),
        (36.789758, -118.565137),
        (36.789674, -118.564927),
        (36.789210, -118.564049),
        (36.788961, -118.563710),
        (36.788785, -118.563219),
        (36.788736, -118.562368),
        (36.788691, -118.561601),
        (36.788678, -118.561156),
        (36.789003, -118.559827),
        (36.789024, -118.559657),
        (36.788865, -118.559550),
        (36.788818, -118.559257),
        (36.788729, -118.558970),
        (36.788717, -118.557575),
        (36.788646, -118.557200),
        (36.788517, -118.556510),
        (36.788517, -118.555804),
        (36.788607, -118.555347),
        (36.788689, -118.554893),
        (36.789001, -118.553820),
        (36.789149, -118.553474),
        (36.789252, -118.553270),
        (36.789289, -118.553058),
        (36.788876, -118.552680),
        (36.788637, -118.552611),
        (36.788391, -118.552508),
        (36.787971, -118.552178),
        (36.787465, -118.552155),
        (36.787029, -118.553048),
        (36.786896, -118.553968),
        (36.786814, -118.554298),
        (36.786516, -118.555184),
        (36.786432, -118.555779),
        (36.786336, -118.556112),
        (36.786383, -118.556458),
        (36.786320, -118.556871),
        (36.786175, -118.557611),
        (36.785949, -118.558351),
        (36.785487, -118.558627),
        (36.785534, -118.559083),
        (36.785702, -118.559537),
        (36.786080, -118.560167),
        (36.786406, -118.560870),
        (36.786643, -118.561390),
        (36.786879, -118.562104),
        (36.787064, -118.562763),
        (36.786986, -118.563890),
        (36.787270, -118.564292),
        (36.787412, -118.564692),
        (36.787824, -118.565695),
        (36.788176, -118.566186),
        (36.788348, -118.566296),
        (36.788973, -118.566867),
        (36.789111, -118.567202),
        (36.789158, -118.568219),
        (36.789386, -118.568954),
        (36.789590, -118.569756),
        (36.789940, -118.571140),
        (36.790135, -118.571460),
        (36.790569, -118.572594),
        (36.791355, -118.573814),
        (36.791587, -118.574200),
        (36.792084, -118.575069),
        (36.792221, -118.576011),
        (36.792253, -118.576649),
        (36.792279, -118.577491),
        (36.792436, -118.577776),
        (36.792524, -118.578669),
        (36.792734, -118.579117),
        (36.792727, -118.579383),
        (36.792878, -118.579868),
        (36.792835, -118.580190),
        (36.792812, -118.580812),
        (36.792762, -118.581890),
        (36.792715, -118.582260),
        (36.792545, -118.582714),
        (36.792601, -118.582995),
        (36.792531, -118.583145),
        (36.792477, -118.583481),
        (36.792552, -118.583749),
        (36.792449, -118.584334),
        (36.792496, -118.584800),
        (36.792284, -118.585173),
        (36.792152, -118.586107),
        (36.792198, -118.586372),
        (36.792402, -118.587088),
        (36.792718, -118.586967),
        (36.792777, -118.586614),
        (36.792878, -118.585803),
        (36.793007, -118.585554),
        (36.793267, -118.585114),
        (36.793506, -118.585042),
        (36.793716, -118.585179),
        (36.793965, -118.584984),
        (36.794279, -118.584130),
        (36.794393, -118.584208),
        (36.794556, -118.584382),
        (36.794610, -118.583799),
        (36.794827, -118.583162),
        (36.795154, -118.582872),
        (36.795325, -118.582837),
        (36.795636, -118.582912),
        (36.795896, -118.583097),
        (36.796039, -118.583302),
        (36.796185, -118.583738),
        (36.796505, -118.583560),
        (36.796396, -118.584642),
        (36.796243, -118.584779),
    ]

    static let southCreekFalls: [(Double, Double)] = [
        (35.976242, -118.500188),
        (35.976354, -118.500067),
        (35.976553, -118.499845),
        (35.976695, -118.499641),
        (35.976915, -118.499507),
        (35.977030, -118.499433),
        (35.977115, -118.499131),
        (35.977261, -118.498998),
        (35.977498, -118.498944),
        (35.977763, -118.499044),
        (35.977971, -118.499398),
        (35.978059, -118.499638),
        (35.978054, -118.499895),
        (35.978327, -118.499990),
        (35.978566, -118.499869),
        (35.978708, -118.499977),
        (35.978819, -118.499904),
        (35.979117, -118.500077),
        (35.979221, -118.500249),
        (35.979408, -118.500341),
        (35.979568, -118.500368),
        (35.979830, -118.500475),
        (35.980322, -118.500543),
        (35.980431, -118.500625),
        (35.980592, -118.500645),
        (35.980781, -118.500685),
        (35.980930, -118.500856),
        (35.981133, -118.500896),
        (35.981255, -118.500915),
        (35.981337, -118.500729),
        (35.981573, -118.500825),
        (35.981853, -118.500902),
        (35.981872, -118.500878),
        (35.982067, -118.500899),
        (35.982196, -118.500722),
        (35.982299, -118.500640),
        (35.982526, -118.500880),
        (35.982673, -118.500906),
        (35.982971, -118.500920),
        (35.983139, -118.500867),
        (35.983282, -118.500877),
        (35.983415, -118.501035),
        (35.983587, -118.500986),
        (35.983731, -118.500741),
        (35.983840, -118.500727),
        (35.984051, -118.500754),
        (35.984230, -118.500685),
        (35.984317, -118.500535),
        (35.984516, -118.500552),
        (35.984762, -118.500556),
        (35.984920, -118.500475),
        (35.985089, -118.500387),
        (35.985303, -118.500344),
        (35.985467, -118.500200),
        (35.985708, -118.500234),
        (35.985852, -118.500267),
        (35.986002, -118.500338),
        (35.986221, -118.500171),
        (35.986306, -118.500079),
        (35.986539, -118.499795),
        (35.986687, -118.499553),
        (35.986838, -118.499526),
        (35.987033, -118.499365),
        (35.987162, -118.499297),
        (35.987302, -118.499189),
        (35.987451, -118.499110),
        (35.987627, -118.498829),
        (35.987655, -118.498499),
        (35.987753, -118.498195),
        (35.987845, -118.497935),
        (35.987963, -118.497688),
        (35.987978, -118.497631),
        (35.988070, -118.497411),
        (35.988337, -118.497218),
        (35.988365, -118.497064),
        (35.988540, -118.496783),
        (35.988624, -118.496621),
        (35.988801, -118.496350),
        (35.989095, -118.495901),
        (35.989166, -118.495768),
        (35.989118, -118.495557),
        (35.989148, -118.495203),
        (35.989205, -118.495022),
        (35.989242, -118.494799),
        (35.989456, -118.494291),
        (35.989519, -118.494198),
        (35.989689, -118.494131),
        (35.989826, -118.493876),
        (35.990007, -118.493746),
        (35.990185, -118.493745),
        (35.990318, -118.493722),
        (35.990360, -118.493408),
        (35.990501, -118.493131),
        (35.990647, -118.493032),
        (35.990752, -118.492777),
        (35.990847, -118.492567),
        (35.990945, -118.492482),
        (35.991054, -118.492228),
        (35.991091, -118.492096),
        (35.991240, -118.491942),
        (35.991368, -118.491774),
        (35.991479, -118.491722),
        (35.991743, -118.491456),
        (35.991889, -118.491369),
        (35.991982, -118.491223),
        (35.992165, -118.491064),
        (35.992144, -118.490945),
        (35.992201, -118.490752),
        (35.992294, -118.490562),
        (35.992388, -118.490422),
        (35.992486, -118.490198),
        (35.992727, -118.489734),
        (35.993012, -118.489705),
        (35.993265, -118.489592),
        (35.993283, -118.489471),
        (35.993356, -118.489353),
        (35.993697, -118.489018),
        (35.993815, -118.488845),
        (35.993828, -118.488801),
        (35.994048, -118.488872),
        (35.994094, -118.489000),
        (35.994099, -118.488913),
        (35.994046, -118.488779),
        (35.993856, -118.488503),
        (35.993790, -118.488317),
        (35.993704, -118.488081),
        (35.993686, -118.487979),
        (35.993791, -118.487794),
        (35.993911, -118.487709),
        (35.994104, -118.487548),
        (35.994115, -118.487392),
        (35.994224, -118.487256),
        (35.994266, -118.487166),
        (35.994324, -118.486846),
        (35.994458, -118.486625),
        (35.994544, -118.486510),
        (35.994592, -118.486266),
        (35.994468, -118.486062),
        (35.994411, -118.485906),
        (35.994400, -118.485718),
        (35.994445, -118.485573),
        (35.994529, -118.485417),
        (35.994389, -118.485504),
        (35.994383, -118.485241),
        (35.994315, -118.485191),
        (35.994511, -118.485057),
        (35.994399, -118.484871),
        (35.994245, -118.484900),
        (35.994143, -118.484963),
        (35.994052, -118.484895),
        (35.993886, -118.484758),
    ]

}
