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
    @ObservedObject var routeCache = RouteCache.shared
    @ObservedObject var tileCache = TileCacheManager.shared
    @ObservedObject var dayVisibility = DayRouteVisibility.shared
    @ObservedObject var notesService = TripNotesService.shared
    @EnvironmentObject var viewModel: ChatViewModel

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.8, longitude: -119.3),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )
    @State private var selectedFriend: FriendLocation?
    @State private var showingList = false
    @State private var showingTrail: TrailRoute?
    @State private var dayRoutesExpanded: Bool = false
    @State private var showingOfflinePrompt: Bool = false
    @State private var showingOfflineSheet: Bool = false
    /// Non-nil while the user is actively dropping a new note. The annotation
    /// reference lets the user drag the pin on the map; the parent reads its
    /// final coordinate at Save time.
    @State private var draftNote: DraftNoteAnnotation?
    @State private var draftNoteText: String = ""
    @State private var viewingNote: TripNote?
    @AppStorage("ge136c.hasPromptedOfflineDownload") private var hasPromptedOfflineDownload: Bool = false

    var body: some View {
        ZStack {
            MainTripMap(
                region: $region,
                selectedFriend: $selectedFriend,
                draftAnnotation: draftNote,
                onSelectNote: { note in
                    viewingNote = note
                }
            )
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

                if draftNote != nil {
                    draftNoteCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()

            // Vertically stacked action buttons on the left side, ~70% size.
            HStack(spacing: 0) {
                VStack(spacing: 7) {
                    Spacer()
                    sideButton(icon: "list.bullet", text: "Live") { showingList.toggle() }
                    Menu {
                        ForEach(TrailRoute.allCases) { trail in
                            Button(trail.title) { showingTrail = trail }
                        }
                    } label: {
                        sideButtonLabel(icon: "figure.hiking", text: "Trails")
                    }
                    daysSideButton
                    sideButton(icon: "scope", text: "Fit") { fitAllPoints() }
                    sideButton(icon: "note.text.badge.plus", text: "Notes") {
                        startNewNote()
                    }
                    offlineSideButton
                    Spacer()
                }
                .padding(.leading, 8)
                Spacer()
            }
        }
        .sheet(isPresented: $showingOfflineSheet) {
            OfflineDownloadSheet()
        }
        .alert("Download offline trip data?", isPresented: $showingOfflinePrompt) {
            Button("Not now", role: .cancel) { }
            Button("Open downloader") { showingOfflineSheet = true }
        } message: {
            Text("Cell service drops in the Sierras. Pre-download the OSM topo tiles and driving routes for the trip area now while you have Wi-Fi.")
        }
        .sheet(isPresented: $showingList) {
            friendListSheet
        }
        .sheet(item: $showingTrail) { trail in
            TrailSheet(trail: trail)
        }
        .sheet(item: $viewingNote) { note in
            TripNoteDetailSheet(note: note)
        }
        .onAppear {
            initializeRegionFromTripConfig()
            maybePromptOfflineDownload()
        }
    }

    private func maybePromptOfflineDownload() {
        guard !hasPromptedOfflineDownload else { return }
        guard tileCache.cachedTileCount == 0 else {
            hasPromptedOfflineDownload = true
            return
        }
        // Brief delay so the prompt doesn't fight initial layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showingOfflinePrompt = true
            hasPromptedOfflineDownload = true
        }
    }

    private var daysSideButton: some View {
        let days = scheduleManager.tripData?.days ?? []
        let allHidden = days.indices.allSatisfy { !dayVisibility.isVisible($0) }
        return Menu {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Button(action: { dayVisibility.toggle(index) }) {
                    HStack {
                        if dayVisibility.isVisible(index) {
                            Image(systemName: "checkmark")
                        }
                        Text(day.title)
                    }
                }
            }
            if !days.isEmpty {
                Divider()
                Button("Show all") { dayVisibility.showAll() }
                Button("Hide all", role: .destructive) {
                    dayVisibility.hiddenIndices = Set(0..<days.count)
                }
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Image(systemName: allHidden ? "calendar.badge.exclamationmark" : "calendar")
                        .font(.system(size: 12, weight: .semibold))
                    // Tiny color dots indicating which days are visible
                    if !days.isEmpty {
                        HStack(spacing: 1) {
                            ForEach(0..<days.count, id: \.self) { i in
                                Circle()
                                    .fill(dayVisibility.isVisible(i) ? TripTheme.dayColor(i) : Color.gray.opacity(0.3))
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .offset(y: 10)
                    }
                }
                Text("Routes")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(TripTheme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 52)
            .background(TripTheme.surface)
            .cornerRadius(12)
            .shadow(radius: 1.5)
        }
    }

    private var offlineSideButton: some View {
        let tilesDone = tileCache.cachedTileCount > 0
        let routesDone = !routeCache.cached.isEmpty
        let icon: String = {
            if tilesDone && routesDone { return "checkmark.circle.fill" }
            return "arrow.down.circle"
        }()
        let label: String = {
            if tilesDone && routesDone { return "Saved" }
            if tilesDone || routesDone { return "Partial" }
            return "Offline"
        }()
        return Button(action: { showingOfflineSheet = true }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor((tilesDone && routesDone) ? .green : TripTheme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 52)
            .background(TripTheme.surface)
            .cornerRadius(12)
            .shadow(radius: 1.5)
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

    private func sideButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sideButtonLabel(icon: icon, text: text)
        }
    }

    private func sideButtonLabel(icon: String, text: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 9, design: .monospaced))
        }
        .foregroundColor(TripTheme.onSurfaceText)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 52)
        .background(TripTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TripTheme.stroke, lineWidth: 0.5))
        .cornerRadius(12)
        .shadow(radius: 1.5)
    }

    @ViewBuilder
    private var routeLinksCard: some View {
        if let days = scheduleManager.tripData?.days, !days.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { dayRoutesExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Text("Day Routes")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(TripTheme.primaryText)
                            .fontWeight(.bold)

                        // Color legend strip (always visible)
                        HStack(spacing: 4) {
                            ForEach(Array(days.enumerated()), id: \.element.id) { index, _ in
                                Circle()
                                    .fill(TripTheme.dayColor(index))
                                    .frame(width: 8, height: 8)
                            }
                        }

                        Spacer()
                        Image(systemName: dayRoutesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if dayRoutesExpanded {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(TripTheme.dayColor(index))
                                .frame(width: 10, height: 10)
                            Text(day.title)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(TripTheme.primaryText)
                            Spacer()
                            if let gURL = day.googleMapsURL {
                                Link(destination: gURL) {
                                    routeButtonLabel(text: "Google", icon: "map", filled: false)
                                }
                            }
                        }
                    }
                    Text(routeCacheHint)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .background(TripTheme.surface)
            .cornerRadius(10)
            .shadow(radius: 2)
        }
    }

    private var routeCacheHint: String {
        let count = routeCache.cached.count
        if count == 0 {
            return "Pre-cache routes from Info → Offline Trip Map to see them drawn on this map."
        }
        return "\(count) day route(s) drawn from cached OSM data."
    }

    private func routeButtonLabel(text: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundColor(filled ? .white : TripTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(filled ? TripTheme.accent : TripTheme.accentSoft)
        .cornerRadius(8)
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
        .background(TripTheme.surface)
        .cornerRadius(12)
        .shadow(radius: 4)
    }

    /// Sticky-note draft card shown while the user is positioning + typing a
    /// new pin. The map shows a draggable yellow placeholder; this card
    /// captures the body and exits the mode on Save / Cancel.
    private var draftNoteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "note.text.badge.plus")
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.10))
                Text("New note")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
                Spacer()
                Text("Drag pin to refine")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            }

            TextField("What's here?", text: $draftNoteText, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(TripTheme.background)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TripTheme.stroke, lineWidth: 0.5))
                .cornerRadius(8)

            HStack(spacing: 8) {
                Button(action: { cancelDraftNote() }) {
                    Text("Cancel")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(TripTheme.background)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TripTheme.stroke, lineWidth: 0.5))
                        .cornerRadius(8)
                }
                Button(action: { saveDraftNote() }) {
                    Text("Save note")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canSaveDraft ? TripTheme.accent : TripTheme.accent.opacity(0.4))
                        .cornerRadius(8)
                }
                .disabled(!canSaveDraft)
            }
        }
        .padding()
        .background(TripTheme.surface)
        .cornerRadius(12)
        .shadow(radius: 4)
    }

    private var canSaveDraft: Bool {
        !draftNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drop a fresh draggable placeholder at the current map center.
    private func startNewNote() {
        // Don't stack drafts — bail if one's already in progress.
        guard draftNote == nil else { return }
        draftNoteText = ""
        draftNote = DraftNoteAnnotation(coordinate: region.center)
    }

    private func cancelDraftNote() {
        draftNote = nil
        draftNoteText = ""
    }

    private func saveDraftNote() {
        guard let draft = draftNote, canSaveDraft else { return }
        let body = draftNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        notesService.addNote(at: draft.coordinate, body: body, author: viewModel.nickname)
        draftNote = nil
        draftNoteText = ""
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
                            HStack(spacing: 10) {
                                FriendRosterAvatar(friend: friend)

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
                .foregroundColor(Color(red: 0, green: 0, blue: 0))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(TripTheme.surface)
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
                VStack(spacing: 16) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.white.opacity(0.18))
                                .cornerRadius(12)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Turn on location to unlock the map")
                                    .font(.system(.headline, design: .monospaced))
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Required to see your dot, the trip stops, and friend locations.")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        FriendLocationToggle()
                            .padding(10)
                            .background(TripTheme.surface)
                            .cornerRadius(10)
                    }
                    .padding(16)
                    .background(TripTheme.accent)
                    .cornerRadius(14)
                    .shadow(color: TripTheme.accent.opacity(0.35), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)

                    Spacer()
                }
            }
        }
    }
}

typealias FestivalMapTab = TripMapTab

// MARK: - Trail routes (GPS tracks from the field)

enum TrailRoute: String, CaseIterable, Identifiable {
    case kingsCanyon
    case southCreek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kingsCanyon: return "Kings Canyon — Bubbs Creek Loop"
        case .southCreek:  return "South Creek Falls / 7 Teacups"
        }
    }

    var subtitle: String {
        switch self {
        case .kingsCanyon: return "~5mi pedestrian loop from Roads End. We'll do a 3mi version."
        case .southCreek:  return "~2mi hike from the road to the falls."
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        let pairs: [(Double, Double)] = {
            switch self {
            case .kingsCanyon: return TripRouteGeometry.kingsCanyonLoop
            case .southCreek:  return TripRouteGeometry.southCreekFalls
            }
        }()
        return pairs.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
    }
}

struct TrailSheet: View {
    let trail: TrailRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trail.title)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                    Text(trail.subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(TripTheme.secondaryText)
                }
            }
            .padding()

            TrailPolylineMap(coordinates: trail.coordinates)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(TripTheme.background)
    }
}

#if os(iOS)
struct TrailPolylineMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        guard coordinates.count >= 2 else { return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)

        let start = MKPointAnnotation()
        start.coordinate = coordinates.first!
        start.title = "Start"
        let end = MKPointAnnotation()
        end.coordinate = coordinates.last!
        end.title = "End"
        map.addAnnotations([start, end])

        map.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(red: 1.0, green: 0.49, blue: 0.08, alpha: 1.0) // GE136C accent
            renderer.lineWidth = 4
            return renderer
        }
    }
}
#else
struct TrailPolylineMap: View {
    let coordinates: [CLLocationCoordinate2D]
    var body: some View { Text("Trail view available on iOS.") }
}
#endif

// MARK: - Per-day route visibility (toggleable from the map side menu)

@MainActor
final class DayRouteVisibility: ObservableObject {
    static let shared = DayRouteVisibility()
    private let key = "ge136c.hiddenDayIndices"

    @Published var hiddenIndices: Set<Int> {
        didSet {
            let str = hiddenIndices.map(String.init).joined(separator: ",")
            UserDefaults.standard.set(str, forKey: key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        let parts = raw.split(separator: ",").compactMap { Int($0) }
        hiddenIndices = Set(parts)
    }

    func isVisible(_ index: Int) -> Bool {
        !hiddenIndices.contains(index)
    }

    func toggle(_ index: Int) {
        if hiddenIndices.contains(index) {
            hiddenIndices.remove(index)
        } else {
            hiddenIndices.insert(index)
        }
    }

    func showAll() {
        hiddenIndices.removeAll()
    }
}

// MARK: - Main trip map (MKMapView wrapper that supports polylines + tile overlay)

#if os(iOS)
struct MainTripMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedFriend: FriendLocation?
    /// Optional in-progress note placeholder. When non-nil, rendered as a
    /// draggable yellow pin so the user can position it before saving.
    var draftAnnotation: DraftNoteAnnotation? = nil
    /// Tap callback for an existing note annotation. Parent presents details.
    var onSelectNote: ((TripNote) -> Void)? = nil
    @ObservedObject private var locationService = FriendLocationService.shared
    @ObservedObject private var scheduleManager = TripScheduleManager.shared
    @ObservedObject private var tileCache = TileCacheManager.shared
    @ObservedObject private var routeCache = RouteCache.shared
    @ObservedObject private var dayVisibility = DayRouteVisibility.shared
    /// Observed so that a fresh selfie arriving over Nostr/BLE forces a
    /// SwiftUI update, which in turn calls updateUIView and re-renders pins.
    @ObservedObject private var selfieStore = PeerSelfieStore.shared
    /// Observed so that newly received Nostr notes appear without a tap.
    @ObservedObject private var notesService = TripNotesService.shared

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setRegion(region, animated: false)
        context.coordinator.lastSyncedRegion = region
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Region: only push when SwiftUI's region meaningfully changed (avoids fighting user panning).
        if !context.coordinator.regionsClose(map.region, region) &&
           !context.coordinator.regionsClose(context.coordinator.lastSyncedRegion, region) {
            map.setRegion(region, animated: true)
            context.coordinator.lastSyncedRegion = region
        }

        // Tile overlay (if user has cached tiles, show them; else stick with Apple base).
        map.removeOverlays(map.overlays)
        if tileCache.cachedTileCount > 0 {
            let overlay = CachedTileOverlay(source: tileCache.preferredSource)
            map.addOverlay(overlay, level: .aboveLabels)
        }

        // Driving route polylines (one per day), color-coded, filtered by visibility.
        if let days = scheduleManager.tripData?.days {
            for (index, day) in days.enumerated() {
                guard dayVisibility.isVisible(index) else { continue }
                guard let cached = routeCache.cached[day.id] else { continue }
                let coords = cached.clCoordinates
                guard coords.count >= 2 else { continue }
                let polyline = DayPolyline(coordinates: coords, count: coords.count)
                polyline.dayIndex = index
                map.addOverlay(polyline, level: .aboveLabels)
            }
        }

        // Annotations: rebuild stops/friends/notes deterministically each pass
        // BUT preserve any DraftNoteAnnotation across rebuilds so an in-progress
        // drag isn't interrupted by unrelated state churn (friend pings, etc.).
        let existing = map.annotations.filter {
            !($0 is MKUserLocation) && !($0 is DraftNoteAnnotation)
        }
        map.removeAnnotations(existing)

        var anns: [MKAnnotation] = []
        for loc in scheduleManager.allLocations {
            guard let c = loc.coordinate else { continue }
            anns.append(TripStopAnnotation(coordinate: c, name: loc.name))
        }
        for friend in locationService.locatedFriends {
            anns.append(FriendAnnotation(friend: friend, isSelected: selectedFriend?.id == friend.id))
        }
        for note in notesService.notes {
            anns.append(TripNoteAnnotation(note: note))
        }
        map.addAnnotations(anns)

        // Sync the draft pin separately: add it the first time it appears,
        // remove it when SwiftUI clears the draft (Save/Cancel).
        let currentDrafts = map.annotations.compactMap { $0 as? DraftNoteAnnotation }
        if let draft = draftAnnotation {
            if !currentDrafts.contains(where: { $0 === draft }) {
                map.addAnnotation(draft)
            }
        } else if !currentDrafts.isEmpty {
            map.removeAnnotations(currentDrafts)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MainTripMap
        var lastSyncedRegion: MKCoordinateRegion = MKCoordinateRegion()

        init(parent: MainTripMap) { self.parent = parent }

        func regionsClose(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
            let cTol = 0.0005
            let sTol = 0.001
            return abs(a.center.latitude - b.center.latitude) < cTol &&
                   abs(a.center.longitude - b.center.longitude) < cTol &&
                   abs(a.span.latitudeDelta - b.span.latitudeDelta) < sTol &&
                   abs(a.span.longitudeDelta - b.span.longitudeDelta) < sTol
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Sync the user-driven region back so SwiftUI's @State stays in sync (without loop).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.regionsClose(self.parent.region, mapView.region) {
                    self.parent.region = mapView.region
                    self.lastSyncedRegion = mapView.region
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let dp = overlay as? DayPolyline {
                let renderer = MKPolylineRenderer(polyline: dp)
                renderer.strokeColor = TripTheme.dayUIColor(dp.dayIndex).withAlphaComponent(0.9)
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // In-progress draft pin: yellow, draggable, no callout.
            if annotation is DraftNoteAnnotation {
                let id = "trip-note-draft"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.displayPriority = .required
                view.isDraggable = true
                view.markerTintColor = UIColor(red: 1.0, green: 0.85, blue: 0.10, alpha: 1.0)
                view.glyphImage = UIImage(systemName: "plus")
                view.glyphTintColor = .black
                return view
            }

            // Yellow sticky-note pin for user-dropped trip notes.
            if let note = annotation as? TripNoteAnnotation {
                let id = "trip-note"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = true
                view.displayPriority = .defaultHigh
                view.isDraggable = false
                view.markerTintColor = UIColor(red: 1.0, green: 0.85, blue: 0.10, alpha: 1.0)
                view.glyphImage = UIImage(systemName: "note.text")
                view.glyphTintColor = .black
                // Truncate to first line for the callout title.
                let firstLine = note.note.body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? note.note.body
                note.title = firstLine.isEmpty ? "Note" : String(firstLine.prefix(48))
                return view
            }

            // For friend annotations, if we have a cached selfie, render a
            // circular avatar pin instead of the system marker. Otherwise fall
            // back to the existing MKMarkerAnnotationView style.
            if let friend = annotation as? FriendAnnotation,
               let avatar = friendSelfie(for: friend) {
                let id = "trip-friend-avatar"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = true
                view.displayPriority = .required
                let ringColor: UIColor = friend.isSelected
                    ? UIColor(red: 0.18, green: 0.55, blue: 0.92, alpha: 1.0)
                    : (friend.friend.isStale ? .systemGray : UIColor(red: 1.00, green: 0.49, blue: 0.08, alpha: 1.0))
                view.image = Self.circularSelfieImage(from: avatar, ringColor: ringColor, diameter: 44)
                view.centerOffset = CGPoint(x: 0, y: -22)
                return view
            }

            let id = "trip-pin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            view.displayPriority = .required

            if let stop = annotation as? TripStopAnnotation {
                view.markerTintColor = UIColor(red: 1.00, green: 0.49, blue: 0.08, alpha: 1.0)
                view.glyphImage = UIImage(systemName: "mappin")
                view.titleVisibility = .visible
                stop.title = stop.name
            } else if let friend = annotation as? FriendAnnotation {
                view.markerTintColor = friend.isSelected
                    ? UIColor(red: 0.18, green: 0.55, blue: 0.92, alpha: 1.0)
                    : (friend.friend.isStale ? .systemGray : UIColor(red: 1.00, green: 0.49, blue: 0.08, alpha: 1.0))
                view.glyphImage = UIImage(systemName: "person.fill")
            }
            return view
        }

        private func friendSelfie(for annotation: FriendAnnotation) -> UIImage? {
            PeerSelfieStore.shared.cachedImage(forNoiseKey: annotation.friend.id)
        }

        /// Renders a circular avatar with a colored ring suitable for an
        /// MKAnnotationView. Diameter is the full output size (image + ring).
        private static func circularSelfieImage(from source: UIImage,
                                                ringColor: UIColor,
                                                diameter: CGFloat) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format)
            return renderer.image { ctx in
                let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                let ringWidth: CGFloat = 2.5
                let imageRect = rect.insetBy(dx: ringWidth, dy: ringWidth)
                let path = UIBezierPath(ovalIn: imageRect)
                ctx.cgContext.saveGState()
                path.addClip()
                source.draw(in: imageRect)
                ctx.cgContext.restoreGState()
                ringColor.setStroke()
                let stroke = UIBezierPath(ovalIn: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
                stroke.lineWidth = ringWidth
                stroke.stroke()
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Selecting the draft pin must not surface the note-detail sheet.
            if view.annotation is DraftNoteAnnotation { return }
            if let friend = view.annotation as? FriendAnnotation {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.selectedFriend = friend.friend
                }
                return
            }
            if let noteAnn = view.annotation as? TripNoteAnnotation {
                let note = noteAnn.note
                mapView.deselectAnnotation(noteAnn, animated: false)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSelectNote?(note)
                }
            }
        }
    }
}

final class DayPolyline: MKPolyline {
    var dayIndex: Int = 0
}

/// 28pt circle that shows the peer's cached selfie if we have one, falling
/// back to a colored dot when we don't. Used by the live-locations roster.
private struct FriendRosterAvatar: View {
    let friend: FriendLocation
    @ObservedObject private var selfieStore = PeerSelfieStore.shared

    var body: some View {
        Group {
            if let image = selfieStore.cachedImage(forNoiseKey: friend.id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ringColor, lineWidth: 1.5))
            } else {
                Circle()
                    .fill(ringColor)
                    .frame(width: 14, height: 14)
                    .frame(width: 28, height: 28)
            }
        }
    }

    private var ringColor: Color {
        friend.isStale ? .gray : TripTheme.accent
    }
}

final class TripStopAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let name: String
    var title: String?

    init(coordinate: CLLocationCoordinate2D, name: String) {
        self.coordinate = coordinate
        self.name = name
        self.title = name
        super.init()
    }
}

final class FriendAnnotation: NSObject, MKAnnotation {
    let friend: FriendLocation
    let isSelected: Bool
    var coordinate: CLLocationCoordinate2D { friend.coordinate }
    var title: String? { friend.nickname }

    init(friend: FriendLocation, isSelected: Bool) {
        self.friend = friend
        self.isSelected = isSelected
        super.init()
    }
}

/// Yellow sticky-note pin annotation for user-dropped trip notes.
final class TripNoteAnnotation: NSObject, MKAnnotation {
    let note: TripNote
    var title: String?
    var coordinate: CLLocationCoordinate2D { note.coordinate }

    init(note: TripNote) {
        self.note = note
        super.init()
    }
}

/// Mutable annotation backing an in-progress note. The user is drawing this
/// pin on the map: drag adjusts `coordinate`, and on Save the parent reads the
/// final coordinate to publish. `@objc dynamic` makes the property KVO-compliant
/// which MKMapView requires for draggable annotations.
final class DraftNoteAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        self.title = "Drag to refine"
        super.init()
    }
}

/// Read-only details for a single trip note. Lets the local author delete
/// their own note from their device (Nostr-side is replaceable, not deletable).
struct TripNoteDetailSheet: View {
    let note: TripNote
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notesService = TripNotesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.10))
                Text(note.author)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(TripTheme.secondaryText)
                }
            }
            Text(note.body)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(TripTheme.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(TripTheme.secondaryText)
            Button(role: .destructive, action: {
                notesService.removeNote(note)
                dismiss()
            }) {
                Label("Remove from my map", systemImage: "trash")
                    .font(.system(.subheadline, design: .monospaced))
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding()
        .background(TripTheme.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.35), .medium])
    }
}
#endif

// MARK: - Offline download sheet (presented from map's left menu)

#if os(iOS)
struct OfflineDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offline trip data")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(TripTheme.primaryText)
                        Text("Topo tiles + driving routes. Download once on Wi-Fi.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                }
                OfflineMapsCard()
            }
            .padding()
        }
        .background(TripTheme.background)
    }
}
#endif

// MARK: - Offline tile caching (OpenStreetMap / OpenTopoMap)

#if os(iOS)
@MainActor
final class TileCacheManager: ObservableObject {
    static let shared = TileCacheManager()

    enum Source: String, CaseIterable, Identifiable {
        case openTopoMap, openStreetMap
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .openTopoMap:   return "OpenTopoMap"
            case .openStreetMap: return "OpenStreetMap"
            }
        }
        var urlTemplate: String {
            switch self {
            case .openTopoMap:   return "https://a.tile.opentopomap.org/{z}/{x}/{y}.png"
            case .openStreetMap: return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
            }
        }
        var attribution: String {
            switch self {
            case .openTopoMap:   return "© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)"
            case .openStreetMap: return "© OpenStreetMap contributors (ODbL)"
            }
        }
        var bytesPerTileEstimate: Int {
            switch self {
            case .openTopoMap:   return 55_000
            case .openStreetMap: return 25_000
            }
        }
    }

    enum Status: Equatable {
        case idle
        case downloading(done: Int, total: Int)
        case complete
        case cancelled
        case failed(String)
    }

    @Published var status: Status = .idle
    @Published var preferredSource: Source {
        didSet { UserDefaults.standard.set(preferredSource.rawValue, forKey: "ge136c.tileSource") }
    }

    enum DetailLevel: String, CaseIterable, Identifiable {
        case low, mid, best
        var id: String { rawValue }
        var label: String {
            switch self {
            case .low:  return "Low"
            case .mid:  return "Mid"
            case .best: return "Best"
            }
        }
        var zooms: ClosedRange<Int> {
            switch self {
            case .low:  return 9...11
            case .mid:  return 9...12
            case .best: return 9...13
            }
        }
        var blurb: String {
            switch self {
            case .low:  return "roads + valleys, LTE-friendly (~20 MB topo)"
            case .mid:  return "town + street detail, WiFi recommended (~77 MB topo)"
            case .best: return "hiking trails visible, WiFi only (~300 MB topo)"
            }
        }
    }

    @Published var preferredDetail: DetailLevel {
        didSet { UserDefaults.standard.set(preferredDetail.rawValue, forKey: "ge136c.tileDetail") }
    }
    @Published private(set) var cachedTileCount: Int = 0
    @Published private(set) var cachedBytes: Int = 0

    private var downloadTask: Task<Void, Never>?
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "Meshy/1.0 iOS (GE136C Sierras trip; mailto:yick@duck.com)"]
        cfg.timeoutIntervalForRequest = 30
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "ge136c.tileSource"),
           let src = Source(rawValue: raw) {
            preferredSource = src
        } else {
            preferredSource = .openTopoMap
        }
        if let raw = UserDefaults.standard.string(forKey: "ge136c.tileDetail"),
           let lvl = DetailLevel(rawValue: raw) {
            preferredDetail = lvl
        } else {
            preferredDetail = .best
        }
        Task { await refreshCacheStats() }
    }

    // Nonisolated so MKTileOverlay (which runs on a background queue) can call it safely.
    nonisolated static func cacheRoot() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ge136c-tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func tileFileURL(source: Source, z: Int, x: Int, y: Int) -> URL {
        cacheRoot()
            .appendingPathComponent(source.rawValue, isDirectory: true)
            .appendingPathComponent("\(z)", isDirectory: true)
            .appendingPathComponent("\(x)", isDirectory: true)
            .appendingPathComponent("\(y).png")
    }

    /// Highest zoom level that has at least one cached tile. Used to cap the
    /// MKTileOverlay's `maximumZ` so zooms past the cached range fall back to
    /// upscaled tiles instead of stalled network requests.
    nonisolated static func maxCachedZoom(source: Source) -> Int? {
        let dir = cacheRoot().appendingPathComponent(source.rawValue, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return nil
        }
        let zooms = entries.compactMap { Int($0) }
        return zooms.max()
    }

    /// Lowest cached zoom — symmetric helper to `maxCachedZoom`. Lets the
    /// overlay set `minimumZ` properly so MKMapView doesn't request tiles
    /// below the cached range (which would hard-fail and blank the view).
    nonisolated static func minCachedZoom(source: Source) -> Int? {
        let dir = cacheRoot().appendingPathComponent(source.rawValue, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return nil
        }
        let zooms = entries.compactMap { Int($0) }
        return zooms.min()
    }

    func cacheRoot() -> URL { Self.cacheRoot() }
    func tileFileURL(source: Source, z: Int, x: Int, y: Int) -> URL {
        Self.tileFileURL(source: source, z: z, x: x, y: y)
    }

    static func tripBBox() -> (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) {
        let coords = TripScheduleManager.shared.allLocations.compactMap { $0.coordinate }
        guard !coords.isEmpty else {
            // Fallback to a sensible default covering Sierras/Central Valley
            return (34.5, 37.4, -120.0, -118.3)
        }
        let lats = coords.map { $0.latitude }
        let lngs = coords.map { $0.longitude }
        let pad = 0.12 // ~13 km
        return (lats.min()! - pad, lats.max()! + pad, lngs.min()! - pad, lngs.max()! + pad)
    }

    static func tilesForBBox(_ bbox: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double),
                             zooms: ClosedRange<Int>) -> [(z: Int, x: Int, y: Int)] {
        var tiles: [(Int, Int, Int)] = []
        for z in zooms {
            let n = pow(2.0, Double(z))
            let xMin = Int(floor((bbox.minLng + 180.0) / 360.0 * n))
            let xMax = Int(floor((bbox.maxLng + 180.0) / 360.0 * n))
            let yMin = Int(floor((1.0 - asinh(tan(bbox.maxLat * .pi / 180.0)) / .pi) / 2.0 * n))
            let yMax = Int(floor((1.0 - asinh(tan(bbox.minLat * .pi / 180.0)) / .pi) / 2.0 * n))
            for x in xMin...xMax {
                for y in yMin...yMax {
                    tiles.append((z, x, y))
                }
            }
        }
        return tiles
    }

    func estimate(zooms: ClosedRange<Int>) -> (tileCount: Int, bytes: Int) {
        let tiles = Self.tilesForBBox(Self.tripBBox(), zooms: zooms)
        return (tiles.count, tiles.count * preferredSource.bytesPerTileEstimate)
    }

    func startDownload(zooms: ClosedRange<Int>? = nil) {
        let zooms = zooms ?? preferredDetail.zooms
        downloadTask?.cancel()
        let source = preferredSource
        let tiles = Self.tilesForBBox(Self.tripBBox(), zooms: zooms)
        status = .downloading(done: 0, total: tiles.count)

        downloadTask = Task { [weak self] in
            guard let self else { return }
            let total = tiles.count
            var done = 0
            let maxConcurrent = 2

            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                var iterator = tiles.makeIterator()

                func enqueueNext() {
                    while inFlight < maxConcurrent, let t = iterator.next() {
                        inFlight += 1
                        group.addTask { [weak self] in
                            await self?.fetchTile(source: source, z: t.z, x: t.x, y: t.y)
                        }
                    }
                }

                enqueueNext()

                while inFlight > 0 {
                    if Task.isCancelled { break }
                    _ = await group.next()
                    inFlight -= 1
                    done += 1
                    if done % 8 == 0 || done == total {
                        await MainActor.run {
                            self.status = .downloading(done: done, total: total)
                        }
                    }
                    enqueueNext()
                }
            }

            await self.refreshCacheStats()
            await MainActor.run {
                if Task.isCancelled {
                    self.status = .cancelled
                } else {
                    self.status = .complete
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        status = .cancelled
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheRoot())
        Task { await refreshCacheStats() }
        status = .idle
    }

    private func fetchTile(source: Source, z: Int, x: Int, y: Int) async {
        let fileURL = tileFileURL(source: source, z: z, x: x, y: y)
        if FileManager.default.fileExists(atPath: fileURL.path) { return }

        let urlStr = source.urlTemplate
            .replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
        guard let url = URL(string: urlStr) else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silently skip on transient failure; caller can resume later.
        }
    }

    private func refreshCacheStats() async {
        let root = cacheRoot()
        var count = 0
        var bytes = 0
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator where url.pathExtension == "png" {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    bytes += size
                    count += 1
                }
            }
        }
        await MainActor.run {
            self.cachedTileCount = count
            self.cachedBytes = bytes
        }
    }
}

// MARK: - OSM driving route cache (OSRM)

struct CachedDayRoute: Codable, Identifiable {
    let dayId: String
    let coordinates: [[Double]]  // [[lng, lat], ...]
    let distanceMeters: Double
    let durationSeconds: Double

    var id: String { dayId }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }
}

@MainActor
final class RouteCache: ObservableObject {
    static let shared = RouteCache()

    enum Status: Equatable {
        case idle
        case downloading(done: Int, total: Int)
        case complete
        case failed(String)
        case cancelled
    }

    @Published var status: Status = .idle
    @Published private(set) var cached: [String: CachedDayRoute] = [:]

    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "GE136C-iOS/1.0 (offline trip companion)"]
        cfg.timeoutIntervalForRequest = 60
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    private init() { loadFromDisk() }

    private func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ge136c-routes.json")
    }

    private func loadFromDisk() {
        let url = cacheURL()
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([CachedDayRoute].self, from: data) else { return }
        cached = Dictionary(uniqueKeysWithValues: arr.map { ($0.dayId, $0) })
    }

    private func persistToDisk() {
        let arr = Array(cached.values)
        guard let data = try? JSONEncoder().encode(arr) else { return }
        try? data.write(to: cacheURL(), options: .atomic)
    }

    var totalDistanceKm: Double {
        cached.values.reduce(0) { $0 + $1.distanceMeters } / 1000.0
    }

    func fetchAll() {
        task?.cancel()
        let days = TripScheduleManager.shared.tripData?.days ?? []
        let total = days.count
        status = .downloading(done: 0, total: total)

        task = Task { [weak self] in
            guard let self else { return }
            var done = 0
            for day in days {
                if Task.isCancelled { break }
                let coords = day.items.compactMap { $0.location?.coordinate }
                if coords.count >= 2 {
                    if let route = try? await self.fetchOne(dayId: day.id, coords: coords) {
                        await MainActor.run {
                            self.cached[route.dayId] = route
                            self.persistToDisk()
                        }
                    }
                }
                done += 1
                await MainActor.run {
                    self.status = .downloading(done: done, total: total)
                }
            }
            await MainActor.run {
                self.status = Task.isCancelled ? .cancelled : .complete
            }
        }
    }

    func cancel() {
        task?.cancel()
        status = .cancelled
    }

    func clear() {
        cached.removeAll()
        try? FileManager.default.removeItem(at: cacheURL())
        status = .idle
    }

    private func fetchOne(dayId: String, coords: [CLLocationCoordinate2D]) async throws -> CachedDayRoute {
        let coordStr = coords
            .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }
            .joined(separator: ";")
        let urlStr = "https://router.project-osrm.org/route/v1/driving/\(coordStr)?overview=full&geometries=geojson"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard let route = decoded.routes.first else { throw URLError(.cannotParseResponse) }
        return CachedDayRoute(
            dayId: dayId,
            coordinates: route.geometry.coordinates,
            distanceMeters: route.distance,
            durationSeconds: route.duration
        )
    }

    private struct OSRMResponse: Decodable {
        let routes: [Route]
        struct Route: Decodable {
            let geometry: Geometry
            let distance: Double
            let duration: Double
            struct Geometry: Decodable {
                let coordinates: [[Double]]
            }
        }
    }
}

final class CachedTileOverlay: MKTileOverlay {
    let source: TileCacheManager.Source

    init(source: TileCacheManager.Source) {
        self.source = source
        // Pass nil so MKTileOverlay never makes live network requests as a fallback.
        // All tile loading goes through our loadTile override (cache-only).
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        // Cap at the highest actually-cached zoom so MKMapView upscales rather
        // than chasing dead network requests when the user zooms past it.
        let highest = TileCacheManager.maxCachedZoom(source: source) ?? 13
        let lowest  = TileCacheManager.minCachedZoom(source: source) ?? 1
        maximumZ = max(1, highest)
        minimumZ = max(1, lowest)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let fileURL = TileCacheManager.tileFileURL(source: source, z: path.z, x: path.x, y: path.y)
        if let data = try? Data(contentsOf: fileURL) {
            result(data, nil)
            return
        }
        // Cache miss — return immediately rather than hitting the network.
        // On airplane mode this prevents the multi-second hang that froze the
        // map when zoomed past the cached zoom range. MKMapView will fall back
        // to the upscaled tile from `maximumZ`.
        result(nil, NSError(domain: "ge136c.tiles", code: 1, userInfo: nil))
    }
}

struct OfflineTripMap: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Sync tile overlay (if user has cached tiles, show them; else stick with Apple base).
        map.removeOverlays(map.overlays)
        if TileCacheManager.shared.cachedTileCount > 0 {
            let tiles = CachedTileOverlay(source: TileCacheManager.shared.preferredSource)
            map.addOverlay(tiles, level: .aboveLabels)
        }

        // Driving route polylines (one per day) on top of tiles.
        for route in RouteCache.shared.cached.values {
            let coords = route.clCoordinates
            guard coords.count >= 2 else { continue }
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            polyline.title = "route"
            map.addOverlay(polyline, level: .aboveLabels)
        }

        // Stop pins.
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        let stops = TripScheduleManager.shared.allLocations.compactMap { loc -> MKPointAnnotation? in
            guard let c = loc.coordinate else { return nil }
            let a = MKPointAnnotation()
            a.coordinate = c
            a.title = loc.name
            return a
        }
        map.addAnnotations(stops)

        // Fit on first render only.
        if context.coordinator.needsInitialFit, !stops.isEmpty {
            context.coordinator.needsInitialFit = false
            var rect = MKMapRect.null
            for a in stops {
                let pt = MKMapPoint(a.coordinate)
                rect = rect.union(MKMapRect(x: pt.x, y: pt.y, width: 1, height: 1))
            }
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40),
                animated: false
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var needsInitialFit = true

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.49, blue: 0.08, alpha: 0.9) // GE136C accent
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct OfflineTripMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cache = TileCacheManager.shared
    @ObservedObject private var routes = RouteCache.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline Trip Map")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                    Text(routes.cached.isEmpty
                         ? "Tiles from local cache. No driving routes yet — pre-cache from Info → Offline Trip Map."
                         : "\(routes.cached.count) day route(s) cached. Total driving distance ~\(Int(routes.totalDistanceKm)) km.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(TripTheme.secondaryText)
                }
            }
            .padding()

            ZStack(alignment: .bottomLeading) {
                OfflineTripMap()
                    .ignoresSafeArea(edges: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cache.preferredSource.attribution)
                    Text("Routing: © OSRM, OpenStreetMap contributors")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55))
                .cornerRadius(4)
                .padding(8)
            }
        }
        .background(TripTheme.background)
    }
}
#endif

#if DEBUG
struct FriendMapView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview omitted: FriendMapView depends on ChatViewModel which has
        // non-trivial init dependencies (keychain, identity bridge). Run on
        // device/simulator to exercise it.
        EmptyView()
    }
}
#endif
