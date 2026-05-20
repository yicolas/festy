//
// FriendMapView.swift
// bitchat
//
// Map view showing friend locations on the trip
//

import SwiftUI
import MapKit
import CoreLocation

/// Map view displaying friend locations
struct FriendMapView: View {
    @ObservedObject var locationService = FriendLocationService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var region = MKCoordinateRegion(
        // Default to Golden Gate Park
        center: CLLocationCoordinate2D(latitude: 37.7694, longitude: -122.4862),
        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    )
    @State private var selectedFriend: FriendLocation?
    @State private var showingList = false
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        ZStack {
            // Map
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: locationService.locatedFriends) { friend in
                MapAnnotation(coordinate: friend.coordinate) {
                    FriendMapPin(friend: friend, isSelected: selectedFriend?.id == friend.id) {
                        selectedFriend = friend
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            // Overlay controls
            VStack {
                // Top bar
                HStack {
                    // Friend count badge
                    friendCountBadge
                    
                    Spacer()
                    
                    // Center on me button
                    Button(action: centerOnUser) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                }
                .padding()
                
                Spacer()
                
                // Selected friend card
                if let friend = selectedFriend {
                    selectedFriendCard(friend)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Bottom controls
                HStack {
                    // List toggle
                    Button(action: { showingList.toggle() }) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("List")
                        }
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(textColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                        .cornerRadius(20)
                        .shadow(radius: 2)
                    }
                    
                    Spacer()
                    
                    // Fit all friends button
                    if !locationService.locatedFriends.isEmpty {
                        Button(action: fitAllFriends) {
                            HStack {
                                Image(systemName: "person.2")
                                Text("Fit All")
                            }
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                            .cornerRadius(20)
                            .shadow(radius: 2)
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingList) {
            friendListSheet
        }
        .onAppear {
            // Center on user location if available
            if let myLocation = locationService.myLocation {
                region.center = myLocation.coordinate
            }
        }
    }
    
    // MARK: - Subviews
    
    private var friendCountBadge: some View {
        let count = locationService.activeFriendLocations.count
        
        return HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
            Text("\(count)")
        }
        .font(.system(.subheadline, design: .monospaced))
        .fontWeight(.bold)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(count > 0 ? Color.blue : Color.gray)
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private func selectedFriendCard(_ friend: FriendLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(friend.isStale ? Color.gray : Color.blue)
                    .frame(width: 12, height: 12)
                
                Text(friend.nickname)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(textColor)
                
                Spacer()
                
                Button(action: { selectedFriend = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("Updated \(timeAgo(friend.timestamp))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if friend.isStale {
                    Text("STALE")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            // Distance from user (if available)
            if let myLocation = locationService.myLocation {
                let distance = myLocation.distance(from: CLLocation(
                    latitude: friend.coordinate.latitude,
                    longitude: friend.coordinate.longitude
                ))
                
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundColor(.secondary)
                    Text(formatDistance(distance))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
    
    private var friendListSheet: some View {
        NavigationView {
            List {
                if locationService.locatedFriends.isEmpty {
                    Text("No friends sharing location")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(locationService.locatedFriends) { friend in
                        Button(action: {
                            selectedFriend = friend
                            region.center = friend.coordinate
                            showingList = false
                        }) {
                            HStack {
                                Circle()
                                    .fill(friend.isStale ? Color.gray : Color.blue)
                                    .frame(width: 10, height: 10)
                                
                                Text(friend.nickname)
                                    .font(.system(.body, design: .monospaced))
                                
                                Spacer()
                                
                                Text(timeAgo(friend.timestamp))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingList = false }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func centerOnUser() {
        if let myLocation = locationService.myLocation {
            withAnimation {
                region.center = myLocation.coordinate
                region.span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            }
        }
    }
    
    private func fitAllFriends() {
        var coordinates = locationService.locatedFriends.map { $0.coordinate }
        
        // Include user location
        if let myLocation = locationService.myLocation {
            coordinates.append(myLocation.coordinate)
        }
        
        guard !coordinates.isEmpty else { return }
        
        // Calculate bounding region
        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.005, (maxLon - minLon) * 1.5)
        )
        
        withAnimation {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }
    
    // MARK: - Helpers
    
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
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 100 {
            return "\(Int(meters))m away"
        } else if meters < 1000 {
            return "\(Int(meters / 10) * 10)m away"
        } else {
            return String(format: "%.1fkm away", meters / 1000)
        }
    }
}

/// Custom map pin for a friend
struct FriendMapPin: View {
    let friend: FriendLocation
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Pin head with initial
                ZStack {
                    Circle()
                        .fill(friend.isStale ? Color.gray : Color.blue)
                        .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                        .shadow(radius: isSelected ? 4 : 2)
                    
                    Text(String(friend.nickname.prefix(1)).uppercased())
                        .font(.system(size: isSelected ? 18 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                // Pin tail
                Triangle()
                    .fill(friend.isStale ? Color.gray : Color.blue)
                    .frame(width: 12, height: 8)
                    .offset(y: -2)
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

/// Triangle shape for pin tail
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tab Integration

/// Trip tab that includes map view
struct TripMapTab: View {
    @ObservedObject var locationService = FriendLocationService.shared
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if locationService.isSharing {
                FriendMapView()
            } else {
                // Prompt to enable location sharing
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "location.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Location Sharing Disabled")
                        .font(.system(.title2, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Text("Enable location sharing to see your friends on the map")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    FriendLocationToggle()
                        .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FriendMapView_Previews: PreviewProvider {
    static var previews: some View {
        FriendMapView()
    }
}
#endif
