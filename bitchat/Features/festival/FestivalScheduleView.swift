//
// FestivalScheduleView.swift
// Festivus Mestivus
//
// Trip mode UI - built on top of bitchat
// Original bitchat: https://github.com/permissionlesstech/bitchat
//
// This is free and unencumbered software released into the public domain.
//

import SwiftUI

struct TripScheduleView: View {
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingStageFilter = false
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.15) : Color(red: 0.97, green: 0.97, blue: 0.99)
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.7) : Color(red: 0.102, green: 0.102, blue: 0.306)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if scheduleManager.isLoaded {
                // Day picker
                dayPickerView
                
                // Now playing banner (if any)
                nowPlayingBanner
                
                // Schedule list
                scheduleListView
            } else {
                Spacer()
                Text("Loading schedule...")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .background(backgroundColor)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduleManager.tripData?.trip.name ?? "Trip")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(textColor)
                
                Text(scheduleManager.tripData?.trip.location ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stage filter button
            Button(action: { showingStageFilter.toggle() }) {
                Image(systemName: scheduleManager.selectedStage == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .foregroundColor(textColor)
            }
            .sheet(isPresented: $showingStageFilter) {
                stageFilterSheet
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - Day Picker
    
    private var dayPickerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(scheduleManager.days, id: \.self) { day in
                    DayPillButton(
                        day: day,
                        displayText: scheduleManager.formatDayForDisplay(day),
                        isSelected: scheduleManager.selectedDay == day,
                        textColor: textColor
                    ) {
                        scheduleManager.selectedDay = day
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(backgroundColor.opacity(0.9))
    }
    
    // MARK: - Now Playing Banner
    
    @ViewBuilder
    private var nowPlayingBanner: some View {
        let nowPlaying = scheduleManager.nowPlaying
        
        if !nowPlaying.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("NOW PLAYING")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                
                ForEach(nowPlaying) { set in
                    HStack {
                        if let stage = scheduleManager.stage(for: set.stage) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(stage.swiftUIColor)
                                .frame(width: 4)
                        }
                        
                        Text(set.artist)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                        
                        Text("@ \(scheduleManager.stage(for: set.stage)?.name ?? set.stage)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color.red.opacity(0.1))
        }
    }
    
    // MARK: - Schedule List
    
    private var scheduleListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let day = scheduleManager.selectedDay {
                    let sets = filteredSets(for: day)
                    
                    if sets.isEmpty {
                        Text("No sets scheduled")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(sets) { set in
                            SetRowView(
                                set: set,
                                stage: scheduleManager.stage(for: set.stage),
                                textColor: textColor
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }
    
    private func filteredSets(for day: String) -> [ScheduledSet] {
        if let stageFilter = scheduleManager.selectedStage {
            return scheduleManager.sets(for: day, stage: stageFilter)
        }
        return scheduleManager.sets(for: day)
    }
    
    // MARK: - Stage Filter Sheet
    
    private var stageFilterSheet: some View {
        NavigationView {
            List {
                Button(action: {
                    scheduleManager.selectedStage = nil
                    showingStageFilter = false
                }) {
                    HStack {
                        Text("All Stages")
                        Spacer()
                        if scheduleManager.selectedStage == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(textColor)
                        }
                    }
                }
                
                if let stages = scheduleManager.tripData?.stages {
                    ForEach(stages) { stage in
                        Button(action: {
                            scheduleManager.selectedStage = stage.id
                            showingStageFilter = false
                        }) {
                            HStack {
                                Circle()
                                    .fill(stage.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                
                                VStack(alignment: .leading) {
                                    Text(stage.name)
                                    Text(stage.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if scheduleManager.selectedStage == stage.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(textColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by Stage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingStageFilter = false
                    }
                }
            }
        }
    }
}

// MARK: - Day Pill Button

struct DayPillButton: View {
    let day: String
    let displayText: String
    let isSelected: Bool
    let textColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(displayText)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? textColor.opacity(0.2) : Color.clear)
                .foregroundColor(isSelected ? textColor : .secondary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? textColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Set Row View

struct SetRowView: View {
    let set: ScheduledSet
    let stage: Stage?
    let textColor: Color
    
    @State private var isNowPlaying = false
    @State private var isUpcoming = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Stage color indicator
            if let stage = stage {
                RoundedRectangle(cornerRadius: 2)
                    .fill(stage.swiftUIColor)
                    .frame(width: 4)
            }
            
            // Time
            VStack(alignment: .leading) {
                Text(set.timeRangeString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 110, alignment: .leading)
            
            // Artist and stage info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(set.artist)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(isNowPlaying ? .red : textColor)
                    
                    if isNowPlaying {
                        Text("LIVE")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    } else if isUpcoming {
                        Text("SOON")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(stage?.name ?? set.stage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onAppear {
            updateStatus()
        }
    }
    
    private func updateStatus() {
        isNowPlaying = set.isNowPlaying()
        isUpcoming = set.isUpcoming(within: 30)
    }
}

// MARK: - Preview

#if DEBUG
struct TripScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        TripScheduleView()
    }
}
#endif
