import SwiftUI

/// Trip mode section added to AppInfoView
struct TripAppInfoSection: View {
    @ObservedObject var tripManager = TripModeManager.shared
    @ObservedObject var scheduleManager = TripScheduleManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trip Mode")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(TripTheme.primaryText)
                .padding(.top, 8)

            Button(action: { tripManager.toggle() }) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tripManager.isEnabled ? "car.fill" : "car")
                        .font(.system(size: 20))
                        .foregroundColor(TripTheme.accent)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(scheduleManager.tripData?.trip.name ?? "GE136C Trip Mode")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(TripTheme.primaryText)

                            Spacer()

                            if tripManager.isEnabled {
                                Text("ON")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(TripTheme.accent)
                                    .cornerRadius(4)
                            }
                        }

                        Text(tripManager.isEnabled
                             ? "Tap to exit trip mode"
                             : "Tap to enable schedule/channels/map trip experience")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let trip = scheduleManager.tripData?.trip {
                            Text(trip.location)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(TripTheme.secondaryText)
                        }
                    }
                }
                .padding()
                .background(tripManager.isEnabled ? TripTheme.accentSoft : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

typealias FestivalAppInfoSection = TripAppInfoSection

#if DEBUG
struct FestivalAppInfoSection_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TripAppInfoSection()
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
