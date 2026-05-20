//
// FestivalChannelsView.swift
// Festivus Mestivus
//
// Trip channels UI - stage channels and custom channels
// Built on top of bitchat: https://github.com/permissionlesstech/bitchat
//
// This is free and unencumbered software released into the public domain.
//

import SwiftUI
import CoreLocation

/// View showing trip-specific channels: stages and custom channels
struct TripChannelsView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @ObservedObject var locationManager = LocationStateManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    @State private var nearestStage: Stage?
    @State private var showLocationPermissionAlert = false
    
    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.7) : Color(red: 0.102, green: 0.102, blue: 0.306)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.15) : Color(red: 0.97, green: 0.97, blue: 0.99)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Nearby Stage Section
                if let nearest = nearestStage {
                    nearbyStageSection(nearest)
                }
                
                // Stage Channels
                stageChannelsSection
                
                // Custom Channels
                if !scheduleManager.customChannels.isEmpty {
                    customChannelsSection
                }
            }
            .padding()
        }
        .background(backgroundColor)
        .onAppear {
            updateNearestStage()
        }
        .onChange(of: locationManager.availableChannels) { _ in
            updateNearestStage()
        }
    }
    
    // MARK: - Nearby Stage
    
    @ViewBuilder
    private func nearbyStageSection(_ stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(stage.swiftUIColor)
                Text("You're near")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(textColor)
            }
            
            Button(action: { joinStageChannel(stage) }) {
                HStack {
                    Circle()
                        .fill(stage.swiftUIColor)
                        .frame(width: 12, height: 12)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(textColor)
                        
                        Text("Tap to join \(stage.channelName)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(stage.swiftUIColor)
                }
                .padding()
                .background(stage.swiftUIColor.opacity(0.15))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Stage Channels
    
    private var stageChannelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stage Channels")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(textColor)
            
            Text("Join a channel to chat with people at that stage")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            
            ForEach(scheduleManager.tripData?.stages ?? []) { stage in
                stageChannelRow(stage)
            }
        }
    }
    
    private func stageChannelRow(_ stage: Stage) -> some View {
        Button(action: { joinStageChannel(stage) }) {
            HStack {
                Circle()
                    .fill(stage.swiftUIColor)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Text(stage.description)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let geohash = stage.geohash {
                    Text(geohash.prefix(5))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Custom Channels
    
    private var customChannelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip Channels")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(textColor)
            
            ForEach(scheduleManager.customChannels) { channel in
                customChannelRow(channel)
            }
        }
    }
    
    private func customChannelRow(_ channel: CustomChannel) -> some View {
        Button(action: { joinCustomChannel(channel) }) {
            HStack {
                Image(systemName: channel.icon)
                    .foregroundColor(channel.swiftUIColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Text(channel.description)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func updateNearestStage() {
        // Get current location and find nearest stage
        guard let location = locationManager.availableChannels.first,
              let stages = scheduleManager.tripData?.stages else {
            nearestStage = nil
            return
        }
        
        // For now, just show first stage as "nearest" 
        // In a real implementation, compare geohashes or coordinates
        nearestStage = stages.first
    }
    
    private func joinStageChannel(_ stage: Stage) {
        // If stage has a geohash, join that location channel
        if let geohash = stage.geohash {
            // Use the location channel system to join
            // This would need integration with LocationStateManager
            print("Joining stage channel: \(stage.name) at \(geohash)")
        }
        
        // Switch to chat tab
        // This would need to communicate with TripMainView
    }
    
    private func joinCustomChannel(_ channel: CustomChannel) {
        // Custom channels use mesh broadcast with a channel tag
        print("Joining custom channel: \(channel.name)")
    }
}

// MARK: - Preview

#if DEBUG
struct TripChannelsView_Previews: PreviewProvider {
    static var previews: some View {
        TripChannelsView()
    }
}
#endif
