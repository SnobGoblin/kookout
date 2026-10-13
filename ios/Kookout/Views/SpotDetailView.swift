import SwiftUI

/// The forecast for one spot, grouped by day, in the spot's own time zone, with the good hours in green.
struct SpotDetailView: View {
    @Environment(SpotStore.self) private var store
    let spot: Spot

    private var forecast: SpotForecast? { store.forecasts[spot.id] }

    var body: some View {
        List {
            if store.failed.contains(spot.id) && forecast == nil {
                Text("Couldn't load the forecast.").foregroundStyle(.red)
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.hours) { hour in
                        HourRow(hour: hour, spot: spot)
                            .listRowBackground(hour.good ? Color.green.opacity(0.18) : nil)
                    }
                } header: {
                    DayHeader(title: group.title, good: group.hours.filter(\.good), spot: spot)
                }
            }
        }
        .navigationTitle(spot.name)
        .overlay { if forecast == nil && !store.failed.contains(spot.id) { ProgressView() } }
        .refreshable { await store.refresh(spot) }
    }

    /// The hours grouped by calendar day at the spot.
    private var days: [(day: Date, title: String, hours: [ForecastHour])] {
        var calendar = Calendar.current
        calendar.timeZone = spot.timeZone
        let grouped = Dictionary(grouping: forecast?.rows ?? []) { calendar.startOfDay(for: $0.time) }
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        style.timeZone = spot.timeZone
        return grouped.keys.sorted().map { day in (day, day.formatted(style), grouped[day]!) }
    }
}

/// "Tuesday 13 October" plus, if there are good hours that day, "Good wind 10–16".
private struct DayHeader: View {
    let title: String
    let good: [ForecastHour]
    let spot: Spot

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let first = good.first, let last = good.last {
                Label("\(spot.sport == .surf ? String(localized: "Good surf") : String(localized: "Good wind")) " +
                      "\(first.time.formatted(.hour(spot.timeZone)))–\(last.end.formatted(.hour(spot.timeZone)))",
                      systemImage: spot.sport.symbol)
                    .foregroundStyle(.green)
                    .textCase(nil)
            }
        }
    }
}

struct HourRow: View {
    let hour: ForecastHour
    let spot: Spot

    var body: some View {
        HStack(spacing: 10) {
            Text(timeLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(minWidth: 64, alignment: .leading)
            Text("\(Int(hour.temp.rounded()))°")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            if spot.sport == .surf {
                Text(waveLabel)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                    .frame(minWidth: 56, alignment: .trailing)
            }
            Spacer()
            Text("\(Units.wind(hour.wind)) (\(hour.gust.map(Units.wind) ?? "–"))")
                .monospacedDigit()
            // The arrow points where the wind blows TO (like yr): wind from the north points down.
            Image(systemName: "arrow.up")
                .rotationEffect(.degrees(hour.deg + 180))
                .frame(width: 20)
            Text(hour.dir)
                .lineLimit(1)
                .fixedSize() // never wrap "WNW"
                .frame(minWidth: 44, alignment: .leading)
        }
        .font(.callout)
    }

    private var waveLabel: String {
        guard let wave = hour.wave else { return "–" }
        let height = "\(Units.wave(wave)) \(Units.waveUnit)"
        return hour.period.map { "\(height) \(Int($0.rounded()))s" } ?? height
    }

    private var timeLabel: String {
        var style = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = spot.timeZone
        guard hour.hours > 1 else { return hour.time.formatted(style) }
        return "\(hour.time.formatted(.hour(spot.timeZone)))–\(hour.end.formatted(.hour(spot.timeZone)))"
    }
}

#Preview {
    NavigationStack { SpotDetailView(spot: Spot.defaults[1]) }.environment(SpotStore())
}
