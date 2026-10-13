import Foundation
import Observation

/// The user's spots and their latest forecasts. All spots are worked out at the same time.
@MainActor @Observable
final class SpotStore {
    var spots: [Spot] = Spot.defaults
    private(set) var forecasts: [Spot.ID: SpotForecast] = [:]
    private(set) var failed: Set<Spot.ID> = []

    func refreshAll() async {
        await withTaskGroup(of: (Spot.ID, SpotForecast?).self) { group in
            for spot in spots {
                group.addTask { (spot.id, try? await KookoutAPI.analyse(spot)) }
            }
            for await (id, forecast) in group {
                if let forecast { forecasts[id] = forecast; failed.remove(id) } else { failed.insert(id) }
            }
        }
    }

    func refresh(_ spot: Spot) async {
        do {
            forecasts[spot.id] = try await KookoutAPI.analyse(spot)
            failed.remove(spot.id)
        } catch {
            failed.insert(spot.id)
        }
    }
}

/// How wind and wave heights are shown. For now this follows the phone's region (feet in the US);
/// settings to change it come later. The rules are always worked out on the numbers as shown, like on the web.
enum Units {
    static var waveInFeet: Bool { Locale.current.measurementSystem == .us }
    static func wind(_ ms: Double) -> String { String(Int(ms.rounded())) }
    static var windUnit: String { "m/s" }
    static func wave(_ m: Double) -> String {
        waveInFeet ? String(Int((m * 3.28084).rounded())) : m.formatted(.number.precision(.fractionLength(1)))
    }
    static var waveUnit: String { waveInFeet ? "ft" : "m" }
}
