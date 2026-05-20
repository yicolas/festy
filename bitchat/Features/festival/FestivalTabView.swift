//
// FestivalTabView.swift
// bitchat
//
// Trip mode with schedule and chat integration
//

import SwiftUI

/// Main trip mode view with tab navigation
/// Integrates schedule viewing with bitchat messaging
struct TripTabView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .schedule
    
    enum TabSelection: String, CaseIterable {
        case schedule = "Schedule"
        case chat = "Chat"
        
        var icon: String {
            switch self {
            case .schedule: return "calendar"
            case .chat: return "message"
            }
        }
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            switch selectedTab {
            case .schedule:
                TripScheduleView()
            case .chat:
                // Return to regular chat
                Text("Switch to Chat tab in main app")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Custom tab bar
            tabBar
        }
    }
    
    private var tabBar: some View {
        HStack {
            ForEach(TabSelection.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.rawValue)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundColor(selectedTab == tab ? textColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

// MARK: - Trip Mode Toggle

/// A view modifier that can be applied to ContentView to enable trip mode
struct TripModeModifier: ViewModifier {
    @Binding var isTripModeEnabled: Bool
    
    func body(content: Content) -> some View {
        if isTripModeEnabled {
            TripTabView()
        } else {
            content
        }
    }
}

extension View {
    func tripMode(enabled: Binding<Bool>) -> some View {
        modifier(TripModeModifier(isTripModeEnabled: enabled))
    }
}

// MARK: - Trip Mode Menu Button

/// Button to toggle trip mode, can be added to app info or settings
struct TripModeButton: View {
    @Binding var isTripModeEnabled: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        Button(action: { isTripModeEnabled.toggle() }) {
            HStack {
                Image(systemName: isTripModeEnabled ? "tent.fill" : "tent")
                    .foregroundColor(textColor)
                
                Text(isTripModeEnabled ? "Exit Trip Mode" : "Enter Trip Mode")
                    .font(.system(.body, design: .monospaced))
                
                Spacer()
                
                if isTripModeEnabled {
                    Text("ON")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(textColor)
                        .cornerRadius(4)
                }
            }
            .padding()
            .background(isTripModeEnabled ? textColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct TripTabView_Previews: PreviewProvider {
    static var previews: some View {
        TripTabView()
    }
}
#endif
