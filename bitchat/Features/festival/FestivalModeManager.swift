import SwiftUI
import Combine

/// Manages trip mode state across the app.
/// Persists to UserDefaults and defaults to enabled for this app's offline-trip UX.
@MainActor
class TripModeManager: ObservableObject {
    static let shared = TripModeManager()

    private let defaults = UserDefaults.standard
    private let enabledKey = "tripModeEnabled"
    private let hasLaunchedKey = "tripModeHasLaunched"
    private let legacyEnabledKey = "festivalModeEnabled"

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: enabledKey)
        }
    }

    private init() {
        if defaults.bool(forKey: hasLaunchedKey) {
            isEnabled = defaults.bool(forKey: enabledKey)
            return
        }

        if defaults.object(forKey: legacyEnabledKey) != nil {
            isEnabled = defaults.bool(forKey: legacyEnabledKey)
        } else {
            isEnabled = true
        }

        defaults.set(isEnabled, forKey: enabledKey)
        defaults.set(true, forKey: hasLaunchedKey)
    }

    func toggle() {
        isEnabled.toggle()
    }

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }
}

typealias FestivalModeManager = TripModeManager
