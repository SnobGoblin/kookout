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
    /// Notifications for this spot; on unless switched off (nil for spots saved before notifications existed).
    var notify: Bool?
    /// Shared with other Kookout users: true or false for spots the user made themselves (on unless switched off),
    /// nil for spots that came from the catalogue or from someone else.
    var shared: Bool?
    /// Who shared it, for spots added from someone else's ("Christian"; nil if they didn't give a name).
    var addedBy: String?
    /// For community spots (shared ones and the built-in ones): the community's version and who changed it last.
    var community: Community.Info?

    var notifies: Bool { notify ?? true }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var sport: Sport { surf != nil ? .surf : powder != nil ? .powder : .wing }
}
