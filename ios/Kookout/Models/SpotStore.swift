import Foundation
import Observation

/// The user's spots and their latest forecasts. Spots are saved on the phone (a JSON file) until
/// accounts and the shared database arrive; all spots are worked out at the same time.
@MainActor @Observable
final class SpotStore {
    var spots: [Spot] { didSet { save() } }
    private(set) var forecasts: [Spot.ID: SpotForecast] = [:]
    private(set) var failed: Set<Spot.ID> = []

    init() {
        spots = (try? JSONDecoder().decode([Spot].self, from: Data(contentsOf: Self.file))) ?? Spot.defaults
    }

    func refreshAll() async {
        let (units, waveUnit) = (Settings.shared.wind.rawValue, Settings.shared.wave.rawValue)
        await withTaskGroup(of: (Spot.ID, SpotForecast?).self) { group in
            for spot in spots {
                group.addTask { (spot.id, try? await KookoutAPI.analyse(spot, units: units, waveUnit: waveUnit)) }
            }
            for await (id, forecast) in group {
                if let forecast { forecasts[id] = forecast; failed.remove(id) } else { failed.insert(id) }
            }
        }
    }

    func refresh(_ spot: Spot) async {
        do {
            forecasts[spot.id] = try await KookoutAPI.analyse(spot, units: Settings.shared.wind.rawValue,
                                                              waveUnit: Settings.shared.wave.rawValue)
            failed.remove(spot.id)
        } catch {
            failed.insert(spot.id)
        }
    }

    func add(_ spot: Spot) { spots.append(spot) }

    func update(_ spot: Spot) {
        guard let i = spots.firstIndex(where: { $0.id == spot.id }) else { return }
        spots[i] = spot
        forecasts[spot.id] = nil // the rules may have changed; worked out again by refresh
    }

    func resetToDefaults() {
        spots = Spot.defaults
        forecasts = [:]
    }

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "spots.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(spots).write(to: Self.file, options: .atomic)
        } catch {
            print("Couldn't save spots: \(error)")
        }
        Notifications.shared.update(spots: spots)
    }
}

/// How wind, waves, temperatures and times are shown (wind and waves are also judged on the rounded
/// numbers as shown, exactly like the web page). Each one can be "automatic", following the phone:
/// wind in m/s in the Nordic countries and knots elsewhere, feet and °F in the US, the phone's own clock.
@MainActor @Observable
final class Settings {
    static let shared = Settings()

    enum WindUnit: String, CaseIterable { case automatic, ms, kn }
    enum WaveUnit: String, CaseIterable { case automatic, m, ft }
    enum TempUnit: String, CaseIterable { case automatic, c, f }
    enum Clock: String, CaseIterable { case automatic, h12, h24 }

    // Wind, waves and the clock also shape the notifications, so the relay hears about changes.
    var windUnit: WindUnit { didSet { save(windUnit.rawValue, "windUnit") } }
    var waveUnit: WaveUnit { didSet { save(waveUnit.rawValue, "waveUnit") } }
    var tempUnit: TempUnit { didSet { UserDefaults.standard.set(tempUnit.rawValue, forKey: "tempUnit") } }
    var clock: Clock { didSet { save(clock.rawValue, "clock") } }
    /// How far ahead notifications look, in hours.
    var notifyHours: Int { didSet { save(notifyHours, "notifyHours") } }
    static let notifyChoices = [12, 24, 48, 72, 120, 168]

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        Notifications.shared.syncSoon()
    }

    private init() {
        let defaults = UserDefaults.standard
        windUnit = defaults.string(forKey: "windUnit").flatMap(WindUnit.init) ?? .automatic
        waveUnit = defaults.string(forKey: "waveUnit").flatMap(WaveUnit.init) ?? .automatic
        tempUnit = defaults.string(forKey: "tempUnit").flatMap(TempUnit.init) ?? .automatic
        clock = defaults.string(forKey: "clock").flatMap(Clock.init) ?? .automatic
        notifyHours = defaults.object(forKey: "notifyHours") as? Int ?? 48
    }

    /// What "automatic" means on this phone. Wind riders in the Nordic countries use m/s, most of
    /// the world knots; feet and °F in the US; the clock the phone itself uses.
    private static var isUS: Bool { Locale.current.measurementSystem == .us }
    static var automaticWind: WindUnit {
        ["NO", "SE", "DK", "FI", "IS"].contains(Locale.current.region?.identifier ?? "") ? .ms : .kn
    }
    static var automaticWave: WaveUnit { isUS ? .ft : .m }
    static var automaticTemp: TempUnit { isUS ? .f : .c }
    static var automaticClock: Clock {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == true ? .h12 : .h24
    }

    /// What each setting means right now.
    var wind: WindUnit { windUnit == .automatic ? Self.automaticWind : windUnit }
    var wave: WaveUnit { waveUnit == .automatic ? Self.automaticWave : waveUnit }
    var temp: TempUnit { tempUnit == .automatic ? Self.automaticTemp : tempUnit }
    /// "48 hours" or "3 days", in the phone's language.
    static func hoursText(_ hours: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = hours % 24 == 0 && hours > 48 ? [.day] : [.hour]
        return formatter.string(from: TimeInterval(hours * 3600)) ?? "\(hours) h"
    }

    var uses12Hour: Bool { (clock == .automatic ? Self.automaticClock : clock) == .h12 }
}

/// Showing and stepping values in the chosen units. Everything is stored in m/s and metres.
@MainActor
enum Units {
    static let knotsPerMS = 1.94384
    static let feetPerM = 3.28084

    static func windShown(_ ms: Double) -> Int {
        Int((Settings.shared.wind == .kn ? ms * knotsPerMS : ms).rounded())
    }
    static func wind(_ ms: Double) -> String { String(windShown(ms)) }
    static var windUnit: String { Settings.shared.wind == .kn ? String(localized: "kn") : "m/s" }
    /// One step up or down in the shown unit (1 m/s or 1 knot), returned in m/s.
    static func stepWind(_ ms: Double, by step: Int) -> Double {
        let shown = Double(windShown(ms) + step)
        return max(0, Settings.shared.wind == .kn ? shown / knotsPerMS : shown)
    }

    static func wave(_ m: Double) -> String {
        Settings.shared.wave == .ft ? String(Int((m * feetPerM).rounded()))
                                         : m.formatted(.number.precision(.fractionLength(1)))
    }
    static var waveUnit: String { Settings.shared.wave == .ft ? "ft" : "m" }

    /// A time in a spot's zone: "15:00" or "3 PM".
    static func time(_ date: Date, zone: TimeZone) -> String {
        format(date, zone: zone, Settings.shared.uses12Hour ? "h a" : "HH:mm")
    }
    /// A range of hours: "10–14", or with a 12-hour clock "10 AM–2 PM" / "3–6 PM".
    static func hours(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        guard Settings.shared.uses12Hour else { return "\(format(start, zone: zone, "HH"))–\(format(end, zone: zone, "HH"))" }
        let sameHalf = format(start, zone: zone, "a") == format(end, zone: zone, "a")
        return sameHalf ? "\(format(start, zone: zone, "h"))–\(format(end, zone: zone, "h a"))"
                        : "\(format(start, zone: zone, "h a"))–\(format(end, zone: zone, "h a"))"
    }
    private static func format(_ date: Date, zone: TimeZone, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current // AM/PM in the phone's language
        formatter.dateFormat = pattern
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    /// Temperatures are stored in °C and shown in °C or °F, as whole degrees.
    static func tempShown(_ c: Double) -> Int {
        Int((Settings.shared.temp == .f ? c * 9 / 5 + 32 : c).rounded())
    }
    static func temp(_ c: Double) -> String { "\(tempShown(c))°" }
    static var tempUnit: String { Settings.shared.temp == .f ? "°F" : "°C" }
    /// One degree up or down in the shown unit, returned in °C.
    static func stepTemp(_ c: Double, by step: Int) -> Double {
        let shown = Double(tempShown(c) + step)
        return Settings.shared.temp == .f ? (shown - 32) * 5 / 9 : shown
    }
    /// One step up or down in the shown unit (0.1 m or 1 ft), returned in metres.
    static func stepWave(_ m: Double, by step: Int) -> Double {
        if Settings.shared.wave == .ft { return max(0, ((m * feetPerM).rounded() + Double(step)) / feetPerM) }
        return max(0, ((m * 10).rounded() + Double(step)) / 10)
    }
}
