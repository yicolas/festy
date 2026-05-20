//
// FriendLocationToggle.swift
// bitchat
//
// UI component for toggling location sharing with friends
//

import SwiftUI
import CoreLocation

/// Toggle control for location sharing in trip mode
struct FriendLocationToggle: View {
    @ObservedObject var locationService = FriendLocationService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingPermissionAlert = false
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main toggle row
            Button(action: toggleLocationSharing) {
                HStack {
                    Image(systemName: locationService.isSharing ? "location.fill" : "location")
                        .foregroundColor(locationService.isSharing ? .blue : textColor)
                        .font(.system(size: 20))
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share Location with Friends")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Text(locationService.isSharing 
                             ? "Sharing with mutual favorites" 
                             : "Only mutual favorites can see your location")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    if locationService.isSharing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            Text("ON")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
                .background(locationService.isSharing ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(locationService.isSharing ? Color.blue.opacity(0.3) : textColor.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Status info when sharing
            if locationService.isSharing {
                VStack(alignment: .leading, spacing: 8) {
                    if let lastBroadcast = locationService.lastBroadcastTime {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.secondary)
                            Text("Last broadcast: \(timeAgo(lastBroadcast))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    let friendCount = locationService.activeFriendLocations.count
                    if friendCount > 0 {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundColor(.secondary)
                            Text("\(friendCount) friend\(friendCount == 1 ? "" : "s") sharing location")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .alert("Location Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable location access in Settings to share your location with friends.")
        }
    }
    
    private func toggleLocationSharing() {
        let status = CLLocationManager.authorizationStatus()
        
        switch status {
        case .notDetermined:
            // Will prompt for permission
            locationService.toggleSharing()
        case .authorizedWhenInUse, .authorizedAlways:
            locationService.toggleSharing()
        case .denied, .restricted:
            showingPermissionAlert = true
        @unknown default:
            locationService.toggleSharing()
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
}

/// Compact location sharing indicator for the festival banner
struct LocationSharingIndicator: View {
    @ObservedObject var locationService = FriendLocationService.shared
    
    var body: some View {
        if locationService.isSharing {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10))
                
                let count = locationService.activeFriendLocations.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(4)
        }
    }
}

/// List of friends' locations
struct FriendLocationList: View {
    @ObservedObject var locationService = FriendLocationService.shared
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friends' Locations")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(textColor)
            
            if locationService.locatedFriends.isEmpty {
                Text("No friends sharing location yet")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(locationService.locatedFriends) { friend in
                    FriendLocationRow(friend: friend)
                }
            }
        }
    }
}

/// Single row showing a friend's location
struct FriendLocationRow: View {
    let friend: FriendLocation
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        HStack {
            // Friend icon
            Circle()
                .fill(friend.isStale ? Color.gray : Color.blue)
                .frame(width: 10, height: 10)
            
            // Name
            Text(friend.nickname)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(friend.isStale ? .secondary : textColor)
            
            Spacer()
            
            // Time ago
            Text(timeAgo(friend.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Stale indicator
            if friend.isStale {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h"
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FriendLocationToggle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FriendLocationToggle()
            FriendLocationList()
        }
        .padding()
    }
}
#endif
