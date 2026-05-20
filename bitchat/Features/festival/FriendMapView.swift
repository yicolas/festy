import SwiftUI
import MapKit
import CoreLocation

private enum TripMapAnnotationItem: Identifiable {
    case friend(FriendLocation)
    case stop(TripLocation)

    var id: String {
        switch self {
        case .friend(let friend):
            return "friend-\(friend.id.hexEncodedString())"
        case .stop(let stop):
            return "stop-\(stop.id)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .friend(let friend):
            return friend.coordinate
        case .stop(let stop):
            return stop.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }
}

/// Map view displaying trip stops (pins) and live friend locations.
struct FriendMapView: View {
    @ObservedObject var locationService = FriendLocationService.shared
    @ObservedObject var scheduleManager = TripScheduleManager.shared

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.8, longitude: -119.3),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )
    @State private var selectedFriend: FriendLocation?
    @State private var showingList = false

    private var mapAnnotations: [TripMapAnnotationItem] {
        let stops: [TripMapAnnotationItem] = scheduleManager.allLocations
            .filter { $0.coordinate != nil }
            .map { .stop($0) }

        let friends = locationService.locatedFriends.map { TripMapAnnotationItem.friend($0) }
        return stops + friends
    }

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: mapAnnotations) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    switch item {
                    case .friend(let friend):
                        FriendMapPin(friend: friend, isSelected: selectedFriend?.id == friend.id) {
                            selectedFriend = friend
                        }
                    case .stop(let stop):
                        TripStopPin(name: stop.name)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    mapBadge(icon: "mappin", text: "\(scheduleManager.allLocations.count) stops")
                    mapBadge(icon: "person.2.fill", text: "\(locationService.activeFriendLocations.count) live")

                    Spacer()

                    Button(action: centerOnUser) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(TripTheme.accent)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                }

                routeLinksCard

                Spacer()

                if let friend = selectedFriend {
                    selectedFriendCard(friend)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack {
                    Button(action: { showingList.toggle() }) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("Live List")
                        }
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.92))
                        .cornerRadius(20)
                        .shadow(radius: 2)
                    }

                    Spacer()

                    Button(action: fitAllPoints) {
                        HStack {
                            Image(systemName: "scope")
                            Text("Fit Route")
                        }
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.92))
                        .cornerRadius(20)
                        .shadow(radius: 2)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingList) {
            friendListSheet
        }
        .onAppear {
            initializeRegionFromTripConfig()
        }
    }

    private func mapBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(.caption, design: .monospaced))
        .fontWeight(.bold)
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TripTheme.accent)
        .cornerRadius(14)
    }

    @ViewBuilder
    private var routeLinksCard: some View {
        if let links = scheduleManager.mapConfig?.routeLinks, !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Organic Maps Routes")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
                    .fontWeight(.bold)

                ForEach(links) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            HStack {
                                Text(link.title)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundColor(TripTheme.accent)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.92))
            .cornerRadius(10)
            .shadow(radius: 2)
        }
    }

    private func selectedFriendCard(_ friend: FriendLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(friend.isStale ? Color.gray : TripTheme.accent)
                    .frame(width: 12, height: 12)

                Text(friend.nickname)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)

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
                    .foregroundColor(TripTheme.secondaryText)

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
        }
        .padding()
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
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
                                    .fill(friend.isStale ? Color.gray : TripTheme.accent)
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
            .navigationTitle("Live Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingList = false }
                }
            }
        }
    }

    private func initializeRegionFromTripConfig() {
        if let lat = scheduleManager.mapConfig?.centerLatitude,
           let lon = scheduleManager.mapConfig?.centerLongitude {
            region.center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            region.span = MKCoordinateSpan(
                latitudeDelta: scheduleManager.mapConfig?.latitudeDelta ?? 1.2,
                longitudeDelta: scheduleManager.mapConfig?.longitudeDelta ?? 1.2
            )
            return
        }

        fitAllPoints()
    }

    private func centerOnUser() {
        if let myLocation = locationService.myLocation {
            withAnimation {
                region.center = myLocation.coordinate
                region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            }
        }
    }

    private func fitAllPoints() {
        var coordinates = scheduleManager.allLocations.compactMap { $0.coordinate }
        coordinates.append(contentsOf: locationService.locatedFriends.map { $0.coordinate })

        if let myLocation = locationService.myLocation {
            coordinates.append(myLocation.coordinate)
        }

        guard !coordinates.isEmpty else { return }

        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.08, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.08, (maxLon - minLon) * 1.4)
        )

        withAnimation {
            region = MKCoordinateRegion(center: center, span: span)
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

private struct TripStopPin: View {
    let name: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundColor(TripTheme.accent)
                .background(Color.white.clipShape(Circle()))

            Text(name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.9))
                .cornerRadius(4)
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
                ZStack {
                    Circle()
                        .fill(friend.isStale ? Color.gray : Color.blue)
                        .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                        .shadow(radius: isSelected ? 4 : 2)

                    Text(String(friend.nickname.prefix(1)).uppercased())
                        .font(.system(size: isSelected ? 18 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Triangle()
                    .fill(friend.isStale ? Color.gray : Color.blue)
                    .frame(width: 12, height: 8)
                    .offset(y: -2)
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

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

struct TripMapTab: View {
    @ObservedObject var locationService = FriendLocationService.shared

    var body: some View {
        VStack(spacing: 0) {
            if locationService.isSharing {
                FriendMapView()
            } else {
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "location.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Live location sharing is off")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)

                    Text("Turn it on to see friend dots layered over the GE136C route pins.")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
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

typealias FestivalMapTab = TripMapTab

#if DEBUG
struct FriendMapView_Previews: PreviewProvider {
    static var previews: some View {
        FriendMapView()
    }
}
#endif
