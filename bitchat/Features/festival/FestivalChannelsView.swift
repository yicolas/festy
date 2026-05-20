import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct TripChannelsView: View {
    @ObservedObject var scheduleManager = TripScheduleManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Trip Channels")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(TripTheme.primaryText)

                Text("Use these channels in Mesh Chat for coordination while offline.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)

                ForEach(scheduleManager.channels) { channel in
                    TripChannelRow(channel: channel)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick usage")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(TripTheme.primaryText)
                    Text("In Chat, type /join #channel-name to enter one of these group channels.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(TripTheme.secondaryText)
                }
                .padding()
                .background(TripTheme.accentSoft)
                .cornerRadius(10)
            }
            .padding()
        }
        .background(TripTheme.background)
    }
}

struct TripChannelRow: View {
    let channel: TripChannel
    @State private var didCopy = false

    var body: some View {
        Button(action: copyJoinCommand) {
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

                Text(didCopy ? "Copied" : "/join")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(didCopy ? TripTheme.accent : TripTheme.secondaryText)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func copyJoinCommand() {
        let command = "/join \(channel.name)"

        #if os(iOS)
        UIPasteboard.general.string = command
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        #endif

        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopy = false
        }
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
