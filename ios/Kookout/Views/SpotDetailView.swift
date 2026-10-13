import SwiftUI

/// The hourly forecast for one spot, grouped by day, in the spot's own time zone.
struct SpotDetailView: View {
    let spot: Spot
    @State private var hours: [ForecastHour] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            ForEach(days, id: \.day) { group in
                Section(group.title) {
                    ForEach(group.hours) { hour in
                        HourRow(hour: hour, timeZone: spot.timeZone)
                    }
                }
            }
        }
        .navigationTitle(spot.name)
        .overlay { if hours.isEmpty && error == nil { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            hours = try await ForecastService.forecast(for: spot)
            error = nil
        } catch {
            self.error = String(localized: "Couldn't load the forecast.")
        }
    }

    /// The hours grouped by calendar day at the spot.
    private var days: [(day: Date, title: String, hours: [ForecastHour])] {
        var calendar = Calendar.current
        calendar.timeZone = spot.timeZone
        let grouped = Dictionary(grouping: hours) { calendar.startOfDay(for: $0.time) }
        return grouped.keys.sorted().map { day in
            (day, day.formatted(.dateTime.weekday(.wide).day().month(.wide).timeZone(spot.timeZone)), grouped[day]!)
        }
    }
}

private extension Date.FormatStyle {
    func timeZone(_ zone: TimeZone) -> Date.FormatStyle {
        var style = self
        style.timeZone = zone
        return style
    }
}

struct HourRow: View {
    let hour: ForecastHour
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            Text(timeLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize() // never cut off "11:00"
                .frame(minWidth: 64, alignment: .leading)
            Text("\(Int(hour.temperature.rounded()))°")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Spacer()
            Text("\(Int(hour.wind.rounded())) (\(hour.gust.map { String(Int($0.rounded())) } ?? "–"))")
                .monospacedDigit()
            // The arrow points where the wind blows TO (like yr): wind from the north points down.
            Image(systemName: "arrow.up")
                .rotationEffect(.degrees(hour.windFrom + 180))
                .frame(width: 20)
            Text(hour.compass)
                .frame(width: 40, alignment: .leading)
        }
        .font(.callout)
    }

    private var timeLabel: String {
        let start = hour.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).timeZone(timeZone))
        guard hour.hours > 1 else { return start }
        let end = hour.time.addingTimeInterval(Double(hour.hours) * 3600)
        return "\(hour.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).timeZone(timeZone)))–" +
               end.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).timeZone(timeZone))
    }
}

#Preview {
    NavigationStack { SpotDetailView(spot: Spot.defaults[1]) }
}
