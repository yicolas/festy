//
// FestivalModeManager.swift
// FestMest
//
// Global state manager for trip mode
//

import SwiftUI
import Combine

/// Manages trip mode state across the app
/// Persists to UserDefaults so trip mode survives app restarts
/// For FestMest, trip mode defaults to ON (true)
@MainActor
class TripModeManager: ObservableObject {
    static let shared = TripModeManager()
    
    private let defaults = UserDefaults.standard
    private let enabledKey = "tripModeEnabled"
    private let hasLaunchedKey = "tripModeHasLaunched"
    
    /// Whether trip mode is currently enabled
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: enabledKey)
        }
    }
    
    private init() {
        // For FestMest: default to true on first launch
        // After first launch, respect user preference
        if defaults.bool(forKey: hasLaunchedKey) {
            // Returning user - use their saved preference
            self.isEnabled = defaults.bool(forKey: enabledKey)
        } else {
            // First launch - default to trip mode ON
            self.isEnabled = true
            defaults.set(true, forKey: enabledKey)
            defaults.set(true, forKey: hasLaunchedKey)
        }
    }
    
    /// Toggle trip mode on/off
    func toggle() {
        isEnabled.toggle()
    }
    
    /// Enable trip mode
    func enable() {
        isEnabled = true
    }
    
    /// Disable trip mode
    func disable() {
        isEnabled = false
    }
}
