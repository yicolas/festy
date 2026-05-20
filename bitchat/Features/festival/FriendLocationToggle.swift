import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#endif

/// Toggle control for location sharing in trip mode
struct FriendLocationToggle: View {
    @ObservedObject var locationService = FriendLocationService.shared
    @State private var showingPermissionAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleLocationSharing) {
                HStack {
                    Image(systemName: locationService.isSharing ? "location.fill" : "location")
                        .foregroundColor(locationService.isSharing ? TripTheme.accent : TripTheme.primaryText)
                        .font(.system(size: 20))
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share live location")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(TripTheme.primaryText)

                        Text(locationService.isSharing
                             ? "Sharing with mutual favorites"
                             : "Only mutual favorites can see your location")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                    }

                    Spacer()

                    if locationService.isSharing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(TripTheme.accent)
                                .frame(width: 8, height: 8)
                            Text("ON")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(TripTheme.accent)
                        }
                    }
                }
                .padding()
                .background(locationService.isSharing ? TripTheme.accentSoft : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(locationService.isSharing ? TripTheme.accent.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if locationService.isSharing {
                VStack(alignment: .leading, spacing: 8) {
                    if let lastBroadcast = locationService.lastBroadcastTime {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.secondary)
                            Text("Last broadcast: \(timeAgo(lastBroadcast))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(TripTheme.secondaryText)
                        }
                    }

                    let friendCount = locationService.activeFriendLocations.count
                    if friendCount > 0 {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundColor(.secondary)
                            Text("\(friendCount) friend\(friendCount == 1 ? "" : "s") sharing location")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(TripTheme.secondaryText)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .alert("Location Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
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
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

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
            .foregroundColor(TripTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(TripTheme.accentSoft)
            .cornerRadius(4)
        }
    }
}

struct FriendLocationList: View {
    @ObservedObject var locationService = FriendLocationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friends' Locations")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(TripTheme.primaryText)

            if locationService.locatedFriends.isEmpty {
                Text("No friends sharing location yet")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
                    .padding(.vertical, 8)
            } else {
                ForEach(locationService.locatedFriends) { friend in
                    FriendLocationRow(friend: friend)
                }
            }
        }
    }
}

struct FriendLocationRow: View {
    let friend: FriendLocation

    var body: some View {
        HStack {
            Circle()
                .fill(friend.isStale ? Color.gray : TripTheme.accent)
                .frame(width: 10, height: 10)

            Text(friend.nickname)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(friend.isStale ? .secondary : TripTheme.primaryText)

            Spacer()

            Text(timeAgo(friend.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

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

#if DEBUG
struct FriendLocationToggle_Previews: PreviewProvider {
    static var previews: some View {
        FriendLocationToggle()
            .padding()
    }
}
#endif
