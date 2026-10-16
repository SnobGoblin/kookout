import SwiftUI

/// The forecast for one spot, grouped by day, in the spot's own time zone, with the good hours in green.
struct SpotDetailView: View {
    @Environment(SpotStore.self) private var store
    let spot: Spot
    /// The latest reading near the spot: nil while the first one loads; .some(nil) when there's no station.
    @State private var live: LiveWind.Station??
    /// Opened from a notification: scroll to this hour once the forecast is there (.some(nil): the first good hour).
    @State private var focus: Date??

    private var forecast: SpotForecast? { store.forecasts[spot.id] }
    /// The latest saved version of the spot (it may have been edited since this screen opened).
    private var current: Spot { store.spots.first { $0.id == spot.id } ?? spot }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if store.failed.contains(spot.id) && forecast == nil {
                    Text("Couldn't load the forecast.").foregroundStyle(.red)
                }
                // Always the same place in the list, so nothing jumps when the reading arrives
                switch live {
                case .some(.some(let station)): LiveWindRow(station: station)
                case .none: LiveWindRow.Loading(station: current.stationName ?? current.community?.stationName)
                case .some(.none): LiveWindRow.Loading(station: nil, done: true)
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
                // At the very end: that real people use this spot (nothing when they're the only one)
                if forecast != nil, let others = current.community.map({ $0.followers - 1 }), others > 0 {
                    Section {} footer: {
                        Text(others == 1 ? String(localized: "1 other rider follows this spot.")
                                         : String(localized: "\(others) other riders follow this spot."))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .onAppear {
                if let f = Notifications.shared.focus, f.spotID == spot.id {
                    focus = .some(f.at)
                    Notifications.shared.focus = nil
                    scrollToFocus(proxy) // if the forecast is already here; otherwise when it comes
                }
            }
            .onChange(of: forecast?.upcomingRows.first?.time, initial: true) { scrollToFocus(proxy) }
        }
        .navigationTitle(current.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit", value: Route.edit(current))
            }
        }
        .overlay { if forecast == nil && !store.failed.contains(spot.id) { ProgressView() } }
        .task(id: "\(spot.id) \(current.station ?? current.community?.station ?? "")") {
            if let known = LiveWind.latest[spot.id] { live = known } // last time's, until the new one comes
            let fresh = await LiveWind.now(for: current)
            LiveWind.latest[spot.id] = fresh
            live = fresh
        }
        .refreshable {
            await store.refresh(spot)
            let fresh = await LiveWind.now(for: current)
            LiveWind.latest[spot.id] = fresh
            live = fresh
        }
    }

    /// To the day of the notification's period (or of the first good hour), its header just below the top: the date
    /// and "Good wind …" say why. Only once: after that the screen scrolls as the person likes.
    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let wanted = focus, let rows = forecast?.upcomingRows, !rows.isEmpty else { return }
        let target = wanted.flatMap { at in rows.first { $0.time.addingTimeInterval(Double($0.hours) * 3600) > at } }
            ?? rows.first(where: \.good)
        focus = nil
        let days = days
        guard let target, let i = days.firstIndex(where: { $0.hours.contains(target) }), i > 0,
              let above = days[i - 1].hours.last else { return } // today: already at the top
        // The list scrolls a row to the very top, under the title bar, so aim at the hour just above the day's header.
        // Twice: it only guesses the height of rows it hasn't drawn yet, so the first jump lands near and the second,
        // once those rows are drawn, lands on it.
        Task {
            proxy.scrollTo(above.id, anchor: .top)
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(above.id, anchor: .top) }
        }
    }

    /// The hours grouped by calendar day at the spot.
    private var days: [(day: Date, title: String, hours: [ForecastHour])] {
        var calendar = Calendar.current
        calendar.timeZone = spot.timeZone
        let grouped = Dictionary(grouping: forecast?.upcomingRows ?? []) { calendar.startOfDay(for: $0.time) }
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
        // Side by side when it fits on one line; otherwise the good hours go under the date, so a range like
        // "7 AM–6 PM" never breaks in the middle (12-hour clocks, large text).
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).fixedSize()
                Spacer()
                goodLabel.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                goodLabel
            }
        }
    }

    @ViewBuilder private var goodLabel: some View {
        if let first = good.first, let last = good.last {
            Label("\(spot.sport == .surf ? String(localized: "Good surf") : String(localized: "Good wind")) " +
                  Units.hours(first.time, last.end, zone: spot.timeZone),
                  systemImage: spot.sport.symbol)
                .foregroundStyle(.green)
                .textCase(nil)
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
                .lineLimit(1)
                .fixedSize() // never wrap "10°" (bold or large text)
                .frame(minWidth: 36, alignment: .trailing)
            if spot.sport == .surf {
                Text(waveLabel)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer()
            // "5 (9)": mean wind and gusts. MET has no gusts outside the Nordic countries: then just "5".
            Text(hour.gust.map { "\(Units.wind(hour.wind)) (\(Units.wind($0)))" } ?? Units.wind(hour.wind))
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

/// "Now 6 (9) ↗ SSW · Hallangsodden, 1.4 km · 12 min ago": the latest measurement near the spot; for a Holfuy
/// station, a button that opens Holfuy's own widget.
struct LiveWindRow: View {
    let station: LiveWind.Station
    @State private var open = false

    /// The same section while the first reading loads, so the forecast below doesn't move when it comes.
    struct Loading: View {
        /// The chosen station's name, when known before the answer (nil: "Automatic" picks one).
        let station: String?
        /// Looked, and found no station with a recent reading (kept, so the forecast below doesn't move).
        var done = false
        var body: some View {
            Section {
                Group {
                    if done { Text("No recent wind reading nearby.") }
                    else if let station { Text("Checking the wind at \(station)…") } else { Text("Checking the wind nearby…") }
                }
                .foregroundStyle(.secondary)
                Text(verbatim: " ").font(.caption)
            } header: {
                Text("Measured now (\(Units.windUnit))")
            }
        }
    }

    var body: some View {
        Section {
            if let live = station.reading {
                HStack(spacing: 8) {
                    Text("Now").bold()
                    Text(live.gust.map { "\(Units.wind(live.wind)) (\(Units.wind($0)))" } ?? Units.wind(live.wind))
                        .monospacedDigit()
                    if let dir = live.dir {
                        Image(systemName: "arrow.up").rotationEffect(.degrees(dir + 180))
                        Text(Compass.points[Int((dir / 22.5).rounded()) % 16])
                    }
                    Spacer()
                }
                Text("\(station.name), \(Measurement.distance(station.km * 1000)) · \(live.time.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let number = station.holfuyNumber {
                // Holfuy's own live widget (they only share their readings with station owners), folded away until opened
                DisclosureGroup("See wind now at \(station.name)", isExpanded: $open) {
                    HolfuyWidget.Embedded(number: number)
                        .frame(height: 175)
                        .listRowInsets(EdgeInsets())
                }
            } else {
                Text("No recent reading from \(station.name).").foregroundStyle(.secondary)
            }
        } header: {
            Text("Measured now (\(Units.windUnit))")
        }
    }
}
