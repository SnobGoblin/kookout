import Foundation
import WidgetKit

/// Keeps the home and Lock Screen widget up to date: tells it the spots (in the user's order) and settings, and the
/// good periods the app worked out, so the widget has something to show without a network. See Shared/WidgetData.swift.
@MainActor
enum WidgetBridge {
    private static var spots: [Spot] = []
    private static var pending: Task<Void, Never>?

    /// The spots changed (added, removed, moved, rules edited).
    static func update(spots: [Spot]) {
        self.spots = spots
        saveSoon()
    }

    /// A setting the widget shows changed (units, clock).
    static func settingsChanged() { saveSoon() }

    /// After a moment's calm (moving spots around changes them many times), save and ask the widget to redraw.
    private static func saveSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
            WidgetCenter.shared.reloadAllTimelines() // the widget asks the relay again with the new spots
        }
    }

    private static func save() {
        let settings = Settings.shared
        let request = Request(spots: spots.map(KookoutAPI.RelaySpot.init), units: settings.wind.rawValue,
                              waveUnit: settings.wave.rawValue, country: Locale.current.region?.identifier)
        guard let body = try? JSONEncoder().encode(request) else { return }
        WidgetData.save(WidgetSpots(spots: spots.map { .init(id: $0.id, name: $0.name, sport: $0.sport.rawValue, tz: $0.timeZoneID) },
                                    units: settings.wind.rawValue, waveUnit: settings.wave.rawValue,
                                    h12: settings.uses12Hour, request: body), WidgetSpots.file)
    }

    private struct Request: Encodable {
        let spots: [KookoutAPI.RelaySpot]
        let units: String, waveUnit: String, country: String?
    }

    /// The app has just worked out forecasts: give the widget the good periods too (it falls back on them offline).
    /// Only the spots the app has a forecast for change; the rest keep what the widget last heard.
    static func save(forecasts: [Spot.ID: SpotForecast], spots: [Spot]) {
        var known = WidgetData.load(WidgetPeriods.self, WidgetPeriods.file) ?? WidgetPeriods()
        let ids = Set(spots.map(\.id))
        known.periods = known.periods.filter { ids.contains($0.key) }
        for spot in spots {
            guard let forecast = forecasts[spot.id] else { continue }
            known.periods[spot.id] = periods(spot, forecast)
        }
        WidgetData.save(known, WidgetPeriods.file)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The same as the relay's answer to the widget (relay/src/widget.js): good periods with the lowest mean wind and
    /// highest gust in them (and the highest wave for surf); for powder spots, the powder days.
    private static func periods(_ spot: Spot, _ forecast: SpotForecast) -> [WidgetPeriod] {
        if spot.sport == .powder {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: forecast.tz) ?? spot.timeZone
            return forecast.powderDays.compactMap { day in
                let rows = forecast.rows.filter { Self.day(of: $0.time, in: calendar) == day }
                guard let first = rows.first, let last = rows.last else { return nil }
                return WidgetPeriod(start: first.time, end: last.end)
            }.filter { $0.end > .now }
        }
        return forecast.upcomingGood.map { p in
            let inside = forecast.rows.filter { $0.time >= p.start && $0.end <= p.end }
            var period = WidgetPeriod(start: p.start, end: p.end)
            if !inside.isEmpty {
                period.lo = inside.map(\.wind).min()
                period.hi = inside.map { $0.gust ?? $0.wind }.max()
                if spot.sport == .surf { period.wave = inside.compactMap(\.wave).max() }
            }
            return period
        }
    }

    private static func day(of date: Date, in calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
