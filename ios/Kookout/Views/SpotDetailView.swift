import SwiftUI

/// The forecast for one spot, grouped by day, in the spot's own time zone, with the good hours in green.
struct SpotDetailView: View {
    @Environment(SpotStore.self) private var store
    let spot: Spot

    private var forecast: SpotForecast? { store.forecasts[spot.id] }
    /// The latest saved version of the spot (it may have been edited since this screen opened).
    private var current: Spot { store.spots.first { $0.id == spot.id } ?? spot }

    var body: some View {
        List {
            if store.failed.contains(spot.id) && forecast == nil {
                Text("Couldn't load the forecast.").foregroundStyle(.red)
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.hours) { hour in
                        HourRow(hour: hour, spot: current)
                            .listRowBackground(hour.good ? Color.goodRow : nil)
                    }
                } header: {
                    DayHeader(title: group.title, good: group.hours.filter(\.good), spot: current)
                }
            }
        }
        .navigationTitle(current.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit", value: Route.edit(current))
            }
        }
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

extension Color {
    /// The background of a good hour: a light tint in light mode, a stronger one in dark mode,
    /// where a faint green on black is hard to see.
    static let goodRow = Color(UIColor { traits in
        UIColor.systemGreen.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.4 : 0.18)
    })
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
                      Units.hours(first.time, last.end, zone: spot.timeZone),
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
        HStack(spacing: 8) {
            Text(timeLabel)
                .monospacedDigit()
                .foregroundStyle(hour.good ? .primary : .secondary)
                .fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            Text(Units.temp(hour.temp))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            if spot.sport == .surf {
                Text(waveLabel)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer()
            Text("\(Units.wind(hour.wind)) (\(hour.gust.map(Units.wind) ?? "–"))")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
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
        // e.g. "1,5 m · 16s" (the unit once, then the period)
        let height = "\(Units.wave(wave)) \(Units.waveUnit)"
        return hour.period.map { "\(height) · \(Int($0.rounded()))s" } ?? height
    }

    private var timeLabel: String {
        hour.hours > 1 ? Units.hours(hour.time, hour.end, zone: spot.timeZone) : Units.time(hour.time, zone: spot.timeZone)
    }
}

#Preview {
    NavigationStack { SpotDetailView(spot: Catalogue.entries[1].spot) }.environment(SpotStore())
}
