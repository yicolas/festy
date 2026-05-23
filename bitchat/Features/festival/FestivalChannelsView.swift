import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class CarAssignmentStore: ObservableObject {
    static let shared = CarAssignmentStore()
    private let key = "ge136c.assignedCarDriver"

    @Published var driver: String? {
        didSet {
            if let v = driver, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        driver = raw.isEmpty ? nil : raw
    }

    /// Normalized hashtag used to filter messages for this car group.
    static func tag(forDriver name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "#car-\(normalized)"
    }

    var assignedTag: String? {
        guard let driver, !driver.isEmpty else { return nil }
        return Self.tag(forDriver: driver)
    }
}

struct TripChannelsView: View {
    @ObservedObject var scheduleManager = TripScheduleManager.shared
    @ObservedObject private var carStore = CarAssignmentStore.shared
    @State private var showingCarPrompt = false
    @State private var driverEntry: String = ""
    /// Called when the user taps a channel. The host should switch to the
    /// chat tab and apply the hashtag filter for that channel.
    var onSelect: ((TripChannel) -> Void)? = nil
    /// Called when the user picks/changes their car group. The host should set
    /// the chat filter to the car tag and switch to the chat tab.
    var onSelectCarTag: ((String) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Trip Channels")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(TripTheme.primaryText)

                Text("Tap a channel to jump straight to its chat. The filter applies to the trip timeline.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)

                ForEach(scheduleManager.channels) { channel in
                    if channel.id == "cars" {
                        carChannelRow(channel: channel)
                    } else {
                        TripChannelRow(channel: channel) {
                            onSelect?(channel)
                        }
                    }
                }
            }
            .padding()
        }
        .background(TripTheme.background)
        .alert("Who's driving your car?", isPresented: $showingCarPrompt) {
            TextField("driver's first name", text: $driverEntry)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                #endif
            Button("Cancel", role: .cancel) {
                driverEntry = ""
            }
            Button("Join car") {
                let name = driverEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                carStore.driver = name
                onSelectCarTag?(CarAssignmentStore.tag(forDriver: name))
                driverEntry = ""
            }
            if carStore.driver != nil {
                Button("Leave current car", role: .destructive) {
                    carStore.driver = nil
                    driverEntry = ""
                }
            }
        } message: {
            Text("Enter your driver's first name. Everyone in the same car uses the same name so messages stay scoped to your vehicle.")
        }
    }

    @ViewBuilder
    private func carChannelRow(channel: TripChannel) -> some View {
        Button(action: {
            driverEntry = carStore.driver ?? ""
            showingCarPrompt = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: channel.icon ?? "car.fill")
                    .foregroundColor(TripTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(TripTheme.primaryText)
                        if let driver = carStore.driver, !driver.isEmpty {
                            Text("· \(driver)'s car")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(TripTheme.accent)
                        }
                    }
                    Text(carStore.driver == nil
                         ? channel.description
                         : "Tap to switch cars or open chat for \(carStore.driver!)'s car.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TripTheme.secondaryText)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct TripChannelRow: View {
    let channel: TripChannel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: channel.icon ?? "number")
                    .foregroundColor(TripTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                    Text(channel.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TripTheme.secondaryText)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

typealias FestivalChannelsView = TripChannelsView

#if DEBUG
struct FestivalChannelsView_Previews: PreviewProvider {
    static var previews: some View {
        TripChannelsView()
    }
}
#endif
