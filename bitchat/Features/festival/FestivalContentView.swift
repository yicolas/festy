//
// FestivalContentView.swift
// Festivus Mestivus
//
// Trip mode UI - built on top of bitchat
// Original bitchat: https://github.com/permissionlesstech/bitchat
//
// This is free and unencumbered software released into the public domain.
//

import SwiftUI

/// Main content wrapper that shows either normal chat or trip mode
/// This view should replace ContentView() in FestMestApp.swift
struct TripContentView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject var tripManager = TripModeManager.shared
    
    var body: some View {
        if tripManager.isEnabled {
            TripMainView()
                .environmentObject(viewModel)
        } else {
            ContentView()
        }
    }
}

/// Trip mode main view with configurable bottom tab navigation
/// Tabs are defined in TripSchedule.json
struct TripMainView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @State private var selectedTabId: String = "schedule"
    
    private var tabs: [TripTab] {
        scheduleManager.tabs
    }
    
    private var selectedTab: TripTab? {
        tabs.first { $0.id == selectedTabId }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.15) : Color(red: 0.97, green: 0.97, blue: 0.99)
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.7) : Color(red: 0.102, green: 0.102, blue: 0.306)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Trip banner
            tripBanner
            
            // Content based on selected tab
            Group {
                if let tab = selectedTab {
                    tabContent(for: tab)
                } else {
                    // Fallback: select first tab
                    Text("Loading...")
                        .onAppear {
                            if let first = tabs.first {
                                selectedTabId = first.id
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Dynamic tab bar
            tabBar
        }
        .background(backgroundColor)
        .onAppear {
            // Default to first tab if current selection is invalid
            if !tabs.contains(where: { $0.id == selectedTabId }), let first = tabs.first {
                selectedTabId = first.id
            }
        }
    }
    
    /// Render content for a tab based on its type
    @ViewBuilder
    private func tabContent(for tab: TripTab) -> some View {
        switch tab.type {
        case .schedule:
            TripScheduleView()
        case .channels:
            TripChannelsView()
        case .chat:
            ContentView()
        case .map:
            TripMapTab()
        case .info:
            TripInfoView()
        case .friends:
            FriendMapView()
        case .groups:
            NavigationStack {
                TripGroupsView()
            }
        case .custom:
            // Placeholder for custom content (could be webview, etc.)
            VStack {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundColor(textColor)
                Text(tab.name)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(textColor)
            }
        }
    }
    
    private var tripBanner: some View {
        HStack {
            Image(systemName: "tent.fill")
                .foregroundColor(textColor)
            
            Text(TripScheduleManager.shared.tripData?.trip.name ?? "Trip Mode")
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(textColor)
            
            Spacer()
            
            Button(action: { TripModeManager.shared.disable() }) {
                Text("Exit")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(textColor.opacity(0.1))
    }
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button(action: { selectedTabId = tab.id }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.name)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundColor(selectedTabId == tab.id ? textColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(backgroundColor)
    }
}

/// Trip info view with mode toggle and tips
struct TripInfoView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var tripManager = TripModeManager.shared
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.15) : Color(red: 0.97, green: 0.97, blue: 0.99)
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.7) : Color(red: 0.102, green: 0.102, blue: 0.306)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Trip header
                if let trip = scheduleManager.tripData?.trip {
                    VStack(alignment: .center, spacing: 8) {
                        Text(trip.name)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(textColor)
                        
                        Text(trip.location)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("Gates: \(trip.gatesOpen) • Music: \(trip.musicStart) - \(trip.musicEnd)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                // Tips section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trip Tips")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    tipRow(icon: "wifi.slash", text: "Mesh chat works without cell service")
                    tipRow(icon: "person.2", text: "Add friends as favorites to find them later")
                    tipRow(icon: "battery.100", text: "BLE mesh is battery efficient")
                    tipRow(icon: "hand.raised.fill", text: "Triple-tap screen to wipe all data")
                }
                
                Divider()
                
                // Exit trip mode
                Button(action: { tripManager.disable() }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Exit Trip Mode")
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(backgroundColor)
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(textColor)
                .frame(width: 24)
            
            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TripContentView_Previews: PreviewProvider {
    static var previews: some View {
        TripMainView()
    }
}
#endif
