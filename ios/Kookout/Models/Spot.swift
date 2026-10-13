import Foundation

enum Sport: String, Codable {
    case wing, surf, powder
}

/// A place the user cares about. For now the app ships with the same default spots as the web page;
/// adding and editing spots comes later.
struct Spot: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var sport: Sport
    /// The spot's own time zone, so forecasts show local time (e.g. "Pacific/Honolulu").
    var timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

extension Spot {
    static let defaults: [Spot] = [
        Spot(id: "drobak", name: "Drøbaksundet", latitude: 59.6732, longitude: 10.6161, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "brattesto", name: "Brattestø", latitude: 59.0561, longitude: 10.9193, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "larkollen", name: "Larkollen lykt", latitude: 59.3232, longitude: 10.6678, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "lysaker", name: "Lysakerfjorden", latitude: 59.9029, longitude: 10.6466, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "orekroken", name: "Ørekroken", latitude: 59.0304, longitude: 11.0105, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "hemsedal", name: "Hemsedal 690 MOH", latitude: 60.8598, longitude: 8.5189, sport: .powder, timeZoneID: "Europe/Oslo"),
        Spot(id: "apelviken", name: "Apelviken", latitude: 57.0832, longitude: 12.2668, sport: .wing, timeZoneID: "Europe/Stockholm"),
        Spot(id: "bore", name: "Borestranda", latitude: 58.7961, longitude: 5.5675, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "movik", name: "Møvik", latitude: 59.3331, longitude: 10.7185, sport: .wing, timeZoneID: "Europe/Oslo"),
        Spot(id: "presteskjaer", name: "Presteskjær", latitude: 59.8091, longitude: 10.7035, sport: .wing, timeZoneID: "Europe/Oslo"),
    ]
}
