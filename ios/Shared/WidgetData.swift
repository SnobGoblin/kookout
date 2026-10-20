import Foundation

/// What the app and its widget share, through an App Group (a folder both can read). Used by both targets.
///
/// - `widget-spots.json` (written by the app): the spots in the user's order, the settings for showing them, and the
///   request the widget sends the relay (POST /widget) to find out when they're good.
/// - `widget-periods.json` (written by both): each spot's good periods as last known. The widget asks the relay about
///   once an hour and saves the answer; the app saves what it worked out itself. Without a network, the widget uses it.
enum WidgetData {
    static let appGroup = "group.com.sternell.kookout"
    /// Kookout's relay (relay/ in the repository).
    static let relay = URL(string: "https://wingfoil-relay.wingfoil-relay.workers.dev")!
    static let kind = "KookoutSpots"
    /// How many spots the widget shows at most.
    static let maxSpots = 3

    /// Tapping a spot in the widget opens it in the app: kookout://spot/<id>.
    static func link(_ spotID: String) -> URL {
        URL(string: "kookout://spot/")!.appending(path: spotID)
    }
    static func spotID(from url: URL) -> String? {
        url.scheme == "kookout" && url.host() == "spot" ? url.pathComponents.dropFirst().first : nil
    }

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let folder, let data = try? Data(contentsOf: folder.appending(path: name)) else { return nil }
        return try? coder.decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let folder, let data = try? coder.encoder.encode(value) else { return }
        try? data.write(to: folder.appending(path: name), options: .atomic)
    }

    private static let coder: (encoder: JSONEncoder, decoder: JSONDecoder) = {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // The relay sends times like "2026-10-13T10:00:00.000Z" (with or without the fraction).
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return (encoder, decoder)
    }()
    static var decoder: JSONDecoder { coder.decoder }
}

/// The app's spots, for the widget (widget-spots.json).
struct WidgetSpots: Codable {
    struct Spot: Codable, Hashable {
        let id: String
        let name: String
        let sport: String   // wing, surf or powder
        let tz: String
        /// Only good periods in the season count (nil: all year).
        var season: Season?
    }
    var spots: [Spot]
    var units: String       // "ms" or "kn"
    var waveUnit: String    // "m" or "ft"
    var h12: Bool
    /// The body of the relay request (POST /widget): the spots' positions and rules in the same order as `spots`.
    var request: Data

    static let file = "widget-spots.json"
}

/// A good period, with the wind (m/s) and waves (m) in it when known. Powder spots: the whole powder day.
struct WidgetPeriod: Codable, Hashable {
    let start: Date
    let end: Date
    var lo: Double?
    var hi: Double?
    var wave: Double?
}

/// The spots' good periods as last known (widget-periods.json), by spot id.
struct WidgetPeriods: Codable {
    var periods: [String: [WidgetPeriod]] = [:]

    static let file = "widget-periods.json"
}

/// A spot as the widget shows it at a given time.
struct WidgetStatus: Hashable {
    let spot: WidgetSpots.Spot
    /// The good period now or next (nil: nothing good in the forecast).
    let period: WidgetPeriod?
    let goodNow: Bool
    /// Whether anything is known about this spot (nil periods: never worked out yet).
    let known: Bool

    /// The spots good soonest: good now first, then by when the next good period starts; ties (and spots with
    /// nothing good) keep the user's own order. With nothing good anywhere, simply the first spots in their order.
    static func soonest(_ spots: [WidgetSpots.Spot], _ known: WidgetPeriods, at now: Date, count: Int = WidgetData.maxSpots) -> [WidgetStatus] {
        let statuses = spots.map { spot -> WidgetStatus in
            let zone = TimeZone(identifier: spot.tz) ?? .current
            let periods = known.periods[spot.id]?.filter { spot.season?.contains($0.start, zone: zone) ?? true }
            let next = periods?.filter { $0.end > now }.min { $0.start < $1.start }
            return WidgetStatus(spot: spot, period: next, goodNow: next.map { $0.start <= now } ?? false, known: periods != nil)
        }
        let rank = { (s: WidgetStatus) -> Date in s.goodNow ? .distantPast : s.period?.start ?? .distantFuture }
        return Array(statuses.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
            .prefix(count))
    }

    /// The moments the widget's picture changes without new data: when a period starts or ends.
    static func changes(_ known: WidgetPeriods, from now: Date, until end: Date) -> [Date] {
        let all = known.periods.values.joined().flatMap { [$0.start, $0.end] }
        return Set(all.filter { $0 > now && $0 < end }).sorted()
    }
}
