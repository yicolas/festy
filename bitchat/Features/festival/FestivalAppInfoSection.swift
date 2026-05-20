//
// FestivalAppInfoSection.swift
// Festivus Mestivus
//
// Trip mode UI - built on top of bitchat
// Original bitchat: https://github.com/permissionlesstech/bitchat
//
// This is free and unencumbered software released into the public domain.
//

import SwiftUI

/// Trip mode section to be added to AppInfoView
/// Usage: Add `TripAppInfoSection()` to the AppInfoView's infoContent VStack
struct TripAppInfoSection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var tripManager = TripModeManager.shared
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    
    private var textColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.7) : Color(red: 0.102, green: 0.102, blue: 0.306)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("Trip Mode")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(textColor)
                .padding(.top, 8)
            
            // Trip mode toggle button
            Button(action: { tripManager.toggle() }) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tripManager.isEnabled ? "tent.fill" : "tent")
                        .font(.system(size: 20))
                        .foregroundColor(textColor)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(scheduleManager.tripData?.trip.name ?? "Trip Mode")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(textColor)
                            
                            Spacer()
                            
                            if tripManager.isEnabled {
                                Text("ON")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(textColor)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(tripManager.isEnabled 
                             ? "Tap to exit trip mode" 
                             : "Tap to enable schedule view and trip features")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let trip = scheduleManager.tripData?.trip {
                            Text("\(trip.location)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(tripManager.isEnabled ? textColor.opacity(0.1) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(textColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TripAppInfoSection_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TripAppInfoSection()
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
