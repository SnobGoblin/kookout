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
        let (units, waveUnit) = (Settings.shared.windUnit.rawValue, Settings.shared.waveUnit.rawValue)
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
            forecasts[spot.id] = try await KookoutAPI.analyse(spot, units: Settings.shared.windUnit.rawValue,
                                                              waveUnit: Settings.shared.waveUnit.rawValue)
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
    }
}

/// How wind and wave heights are shown (and judged: the rules use the rounded numbers as shown,
/// exactly like the web page). Defaults follow the phone's region: feet for waves in the US.
@MainActor @Observable
final class Settings {
    static let shared = Settings()

    enum WindUnit: String, CaseIterable { case ms, kn }
    enum WaveUnit: String, CaseIterable { case m, ft }

    var windUnit: WindUnit { didSet { UserDefaults.standard.set(windUnit.rawValue, forKey: "windUnit") } }
    var waveUnit: WaveUnit { didSet { UserDefaults.standard.set(waveUnit.rawValue, forKey: "waveUnit") } }

    private init() {
        let defaults = UserDefaults.standard
        windUnit = defaults.string(forKey: "windUnit").flatMap(WindUnit.init) ?? .ms
        waveUnit = defaults.string(forKey: "waveUnit").flatMap(WaveUnit.init)
            ?? (Locale.current.measurementSystem == .us ? .ft : .m)
    }
}

/// Showing and stepping values in the chosen units. Everything is stored in m/s and metres.
@MainActor
enum Units {
    static let knotsPerMS = 1.94384
    static let feetPerM = 3.28084

    static func windShown(_ ms: Double) -> Int {
        Int((Settings.shared.windUnit == .kn ? ms * knotsPerMS : ms).rounded())
    }
    static func wind(_ ms: Double) -> String { String(windShown(ms)) }
    static var windUnit: String { Settings.shared.windUnit == .kn ? String(localized: "kn") : "m/s" }
    /// One step up or down in the shown unit (1 m/s or 1 knot), returned in m/s.
    static func stepWind(_ ms: Double, by step: Int) -> Double {
        let shown = Double(windShown(ms) + step)
        return max(0, Settings.shared.windUnit == .kn ? shown / knotsPerMS : shown)
    }

    static func wave(_ m: Double) -> String {
        Settings.shared.waveUnit == .ft ? String(Int((m * feetPerM).rounded()))
                                         : m.formatted(.number.precision(.fractionLength(1)))
    }
    static var waveUnit: String { Settings.shared.waveUnit == .ft ? "ft" : "m" }
    /// One step up or down in the shown unit (0.1 m or 1 ft), returned in metres.
    static func stepWave(_ m: Double, by step: Int) -> Double {
        if Settings.shared.waveUnit == .ft { return max(0, ((m * feetPerM).rounded() + Double(step)) / feetPerM) }
        return max(0, ((m * 10).rounded() + Double(step)) / 10)
    }
}
