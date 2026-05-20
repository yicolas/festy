//
// FestivalContentView+MapTab.swift
// bitchat
//
// Updated FestivalMainView with map tab
// This file updates the FestivalTab enum and FestivalMainView to include the map
//

import SwiftUI

// MARK: - Updated Festival Tab Enum

/// Updated festival tabs including map
enum FestivalTabWithMap: String, CaseIterable {
    case schedule = "Schedule"
    case map = "Map"
    case chat = "Chat"
    case info = "Info"
    
    var icon: String {
        switch self {
        case .schedule: return "calendar"
        case .map: return "map"
        case .chat: return "bubble.left.and.bubble.right"
        case .info: return "info.circle"
        }
    }
}

/// Updated festival main view with map tab
/// Replace FestivalMainView in FestivalContentView.swift with this
struct FestivalMainViewWithMap: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var locationService = FriendLocationService.shared
    @State private var selectedTab: FestivalTabWithMap = .schedule
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Festival banner (hide on map to maximize space)
            if selectedTab != .map {
                festivalBanner
            }
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case .schedule:
                    FestivalScheduleView()
                case .map:
                    FestivalMapTab()
                case .chat:
                    ContentView()
                case .info:
                    FestivalInfoViewWithLocation()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Tab bar
            tabBar
        }
        .background(backgroundColor)
    }
    
    private var festivalBanner: some View {
        HStack {
            Image(systemName: "tent.fill")
                .foregroundColor(textColor)
            
            Text(FestivalScheduleManager.shared.festivalData?.festival.name ?? "Festival Mode")
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(textColor)
            
            // Location sharing indicator
            LocationSharingIndicator()
            
            Spacer()
            
            Button(action: { FestivalModeManager.shared.disable() }) {
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
            ForEach(FestivalTabWithMap.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        ZStack {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20))
                            
                            // Badge for map tab showing friend count
                            if tab == .map && locationService.activeFriendLocations.count > 0 {
                                Text("\(locationService.activeFriendLocations.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .offset(x: 12, y: -8)
                            }
                        }
                        
                        Text(tab.rawValue)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundColor(selectedTab == tab ? textColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(backgroundColor)
    }
}

/// Updated info view with location controls
struct FestivalInfoViewWithLocation: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var festivalManager = FestivalModeManager.shared
    @ObservedObject var scheduleManager = FestivalScheduleManager.shared
    @ObservedObject var locationService = FriendLocationService.shared
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Festival header
                if let festival = scheduleManager.festivalData?.festival {
                    VStack(alignment: .center, spacing: 8) {
                        Text(festival.name)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(textColor)
                        
                        Text(festival.location)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("\(scheduleManager.formatDayForDisplay(festival.dates.start)) - \(scheduleManager.formatDayForDisplay(festival.dates.end))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                Divider()
                
                // Location sharing section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Find Friends")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    FriendLocationToggle()
                    
                    if locationService.isSharing {
                        FriendLocationList()
                            .padding(.top, 8)
                    }
                }
                
                Divider()
                
                // Tips section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trip Tips")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    tipRow(icon: "wifi.slash", text: "Mesh chat works without cell service")
                    tipRow(icon: "person.2", text: "Add friends as favorites to find them later")
                    tipRow(icon: "location.fill", text: "Share location with mutual favorites only")
                    tipRow(icon: "battery.100", text: "BLE mesh is battery efficient")
                    tipRow(icon: "hand.raised.fill", text: "Triple-tap screen to wipe all data")
                }
                
                Divider()
                
                // Exit festival mode
                Button(action: { festivalManager.disable() }) {
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
struct FestivalMainViewWithMap_Previews: PreviewProvider {
    static var previews: some View {
        FestivalMainViewWithMap()
    }
}
#endif
