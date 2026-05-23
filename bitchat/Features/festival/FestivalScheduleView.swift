import SwiftUI

struct TripScheduleView: View {
    @ObservedObject var scheduleManager = TripScheduleManager.shared

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if scheduleManager.isLoaded {
                dayPickerView
                scheduleListView
            } else {
                Spacer()
                Text("Loading trip schedule...")
                    .foregroundColor(TripTheme.secondaryText)
                Spacer()
            }
        }
        .background(TripTheme.background)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(scheduleManager.tripData?.trip.name ?? "GE136C")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(TripTheme.primaryText)

                Text(scheduleManager.tripData?.trip.location ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            }

            Spacer()

            if let selectedDay = scheduleManager.selectedDay,
               let day = scheduleManager.dayData(for: selectedDay),
               let start = day.startTime {
                Text("Start \(start)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TripTheme.accentSoft)
                    .cornerRadius(16)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var dayPickerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(scheduleManager.days.enumerated()), id: \.element) { index, day in
                    let isSelected = scheduleManager.selectedDay == day
                    let dayColor = TripTheme.dayColor(index)
                    Button(action: { scheduleManager.selectedDay = day }) {
                        Text(scheduleManager.formatDayForDisplay(day))
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(isSelected ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? dayColor.opacity(0.18) : Color.clear)
                            .foregroundColor(isSelected ? TripTheme.primaryText : TripTheme.secondaryText)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isSelected ? dayColor : Color.gray.opacity(0.35), lineWidth: 1.5)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var scheduleListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let day = scheduleManager.selectedDay {
                    let items = scheduleManager.items(for: day)

                    if items.isEmpty {
                        Text("No trip items available")
                            .foregroundColor(TripTheme.secondaryText)
                            .padding()
                    } else {
                        ForEach(items) { item in
                            TripItemRowView(item: item)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct TripItemRowView: View {
    let item: TripItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.timeRangeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.accent)
                    .frame(width: 130, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(TripTheme.onSurfaceText)

                    if let address = item.location?.address, !address.isEmpty {
                        Text(address)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(TripTheme.secondaryText)
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                if let drive = item.driveTime, !drive.isEmpty {
                    badge("Drive \(drive)")
                }
                if item.bathroom == true {
                    badge("Bathroom")
                }
                if item.food == true {
                    badge("Food")
                }
            }

            if let presenters = item.presenters, !presenters.isEmpty {
                Text("Presenter(s): \(presenters.joined(separator: ", "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            }

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(TripTheme.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TripTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TripTheme.stroke, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(TripTheme.onSurfaceText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TripTheme.accentSoft)
            .cornerRadius(6)
    }
}

typealias FestivalScheduleView = TripScheduleView

#if DEBUG
struct FestivalScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        TripScheduleView()
    }
}
#endif
