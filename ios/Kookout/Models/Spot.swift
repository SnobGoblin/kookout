import Foundation

enum Sport: String, Codable {
    case wing, surf, powder
}

/// Wing: good when (mean ≥ min and gust ≥ gust) or mean ≥ steady, from one of `dirs`, for `hours` in a row.
/// All speeds in m/s. `sunny` is an optional lower limit for mostly sunny days (sea breeze).
struct WindRule: Codable, Hashable {
    var min: Double = 5
    var gust: Double = 9
    var steady: Double = 6
    var hours: Int = 2
    var daylight = true
    var dirs: [String] = Compass.points
    var sunny: Limits?

    struct Limits: Codable, Hashable {
        var min: Double
        var gust: Double
        var steady: Double
    }
}

/// Surf: good when waves are at least `minWave` m (and the period at least `minPeriod` s, if set),
/// with wind at most `maxWind` m/s from one of `dirs`, for `hours` in a row.
struct SurfRule: Codable, Hashable {
    var minWave: Double = 0.8
    var minPeriod: Double = 0
    var maxWind: Double = 6
    var hours: Int = 2
    var daylight = true
    var dirs: [String] = Compass.points
}

/// Powder: a day with more than `mm` precipitation, colder than `maxTemp` °C, wind under `maxWind` m/s.
struct PowderRule: Codable, Hashable {
    var mm: Double = 10
    var maxTemp: Double = 2
    var maxWind: Double = 8
}

/// A place the user cares about, with the rules for when it's good. The rules are the same as on the
/// web page (rules.js), and the relay works them out.
struct Spot: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    /// The spot's own time zone, so forecasts show local time (e.g. "Pacific/Honolulu").
    var timeZoneID: String
    var wind: WindRule?
    var surf: SurfRule?
    var powder: PowderRule?

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var sport: Sport { surf != nil ? .surf : powder != nil ? .powder : .wing }
}

extension Spot {
    private static let south = ["SE", "SSE", "S", "SSW", "SW"]
    private static let west = ["SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    static let defaults: [Spot] = [
        Spot(id: "drobak", name: "Drøbaksundet", latitude: 59.6732, longitude: 10.6161, timeZoneID: "Europe/Oslo",
             wind: WindRule(dirs: south, sunny: .init(min: 4, gust: 8, steady: 5))),
        Spot(id: "brattesto", name: "Brattestø", latitude: 59.0561, longitude: 10.9193, timeZoneID: "Europe/Oslo",
             wind: WindRule(dirs: ["S", "SSW", "SW", "WSW", "W"])),
        Spot(id: "larkollen", name: "Larkollen", latitude: 59.3232, longitude: 10.6678, timeZoneID: "Europe/Oslo",
             wind: WindRule(dirs: ["S", "SSW", "SW", "WSW"])),
        Spot(id: "lysaker", name: "Lysakerfjorden", latitude: 59.9029, longitude: 10.6466, timeZoneID: "Europe/Oslo",
             wind: WindRule(dirs: [])),
        Spot(id: "orekroken", name: "Ørekroken", latitude: 59.0304, longitude: 11.0105, timeZoneID: "Europe/Oslo",
             wind: WindRule(dirs: ["SW"])),
        Spot(id: "hemsedal", name: "Hemsedal 690 MOH", latitude: 60.8598, longitude: 8.5189, altitude: 690,
             timeZoneID: "Europe/Oslo", powder: PowderRule()),
        Spot(id: "apelviken", name: "Apelviken", latitude: 57.0832, longitude: 12.2668, altitude: 6,
             timeZoneID: "Europe/Stockholm", wind: WindRule(dirs: west)),
        Spot(id: "bore", name: "Borestranda", latitude: 58.7961, longitude: 5.5675, altitude: 6,
             timeZoneID: "Europe/Oslo", wind: WindRule(dirs: west)),
        Spot(id: "movik", name: "Møvik", latitude: 59.3331, longitude: 10.7185, timeZoneID: "Europe/Oslo",
             wind: WindRule(dirs: ["SW", "SSW"])),
        Spot(id: "presteskjaer", name: "Presteskjær", latitude: 59.8091, longitude: 10.7035, altitude: 1,
             timeZoneID: "Europe/Oslo", wind: WindRule(dirs: ["N", "NNE", "NE"])),
    ]
}
