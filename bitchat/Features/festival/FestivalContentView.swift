import SwiftUI

/// Main content wrapper that shows either normal chat or trip mode.
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

struct TripMainView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @State private var selectedTabId: String = "schedule"

    private var tabs: [TripTab] {
        scheduleManager.tabs
    }

    private var selectedTab: TripTab? {
        tabs.first { $0.id == selectedTabId }
    }

    var body: some View {
        VStack(spacing: 0) {
            tripBanner

            Group {
                if let tab = selectedTab {
                    tabContent(for: tab)
                } else {
                    Text("Loading...")
                        .foregroundColor(TripTheme.secondaryText)
                        .onAppear {
                            if let first = tabs.first {
                                selectedTabId = first.id
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            tabBar
        }
        .background(TripTheme.background)
        .onAppear {
            if !tabs.contains(where: { $0.id == selectedTabId }), let first = tabs.first {
                selectedTabId = first.id
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TripTab) -> some View {
        switch tab.type {
        case .schedule:
            TripScheduleView()
        case .channels:
            TripChannelsView()
        case .map:
            TripMapTab()
        case .chat:
            ContentView()
        case .info:
            TripInfoView()
        case .friends:
            FriendMapView()
        case .groups:
            NavigationStack {
                FestivalGroupsView()
            }
        case .custom:
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundColor(TripTheme.accent)
                Text(tab.name)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)
            }
        }
    }

    private var tripBanner: some View {
        HStack {
            Image(systemName: "car.fill")
                .foregroundColor(TripTheme.accent)

            Text(scheduleManager.tripData?.trip.name ?? "Trip Mode")
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(TripTheme.primaryText)

            Spacer()

            Button(action: { TripModeManager.shared.disable() }) {
                Text("Exit")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(TripTheme.accentSoft)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button(action: { selectedTabId = tab.id }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19))
                        Text(tab.name)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundColor(selectedTabId == tab.id ? TripTheme.accent : TripTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTabId == tab.id ? TripTheme.accentSoft : .clear)
                }
            }
        }
        .background(TripTheme.background)
    }
}

struct TripInfoView: View {
    @ObservedObject var tripManager = TripModeManager.shared
    @ObservedObject var scheduleManager = TripScheduleManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let trip = scheduleManager.tripData?.trip {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(trip.name)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(TripTheme.primaryText)

                        Text(trip.subtitle ?? "Offline-first field trip coordination")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)

                        Text("\(scheduleManager.formatDayForDisplay(trip.dates.start)) - \(scheduleManager.formatDayForDisplay(trip.dates.end))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TripTheme.accentSoft)
                    .cornerRadius(12)
                }

                ForEach(scheduleManager.infoSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(TripTheme.primaryText)

                        ForEach(section.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(TripTheme.accent)
                                Text(bullet)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(TripTheme.secondaryText)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }

                Button(action: { tripManager.disable() }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Exit Trip Mode")
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .background(TripTheme.background)
    }
}

typealias FestivalContentView = TripContentView
typealias FestivalMainView = TripMainView
typealias FestivalInfoView = TripInfoView

#if DEBUG
struct FestivalContentView_Previews: PreviewProvider {
    static var previews: some View {
        TripMainView()
    }
}
#endif
