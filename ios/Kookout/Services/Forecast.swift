import Foundation

/// One step of the forecast for a spot: an hour (or, further ahead, six hours), with "good" already worked
/// out by the relay using the spot's rules.
struct ForecastHour: Identifiable, Hashable, Decodable {
    var id: Date { time }
    let time: Date
    let hours: Int
    let symbol: String?
    let temp: Double
    let rain: Double
    let wind: Double          // m/s
    let gust: Double?         // m/s, only given in the hourly part
    let dir: String           // compass direction the wind comes from, e.g. "SSW"
    let deg: Double           // degrees, where the wind comes from
    let wave: Double?         // m, surf spots only
    let period: Double?       // s, surf spots only
    let daylight: Bool
    let good: Bool
    let snow: Bool

    var end: Date { time.addingTimeInterval(Double(hours) * 3600) }
}

/// The relay's answer for one spot.
struct SpotForecast: Decodable {
    let tz: String
    let good: [Period]
    let powderDays: [String]
    let rows: [ForecastHour]

    struct Period: Decodable, Hashable {
        let start: Date
        let end: Date
    }

    /// The hours that haven't ended yet (a forecast fetched last night still starts at last night).
    var upcomingRows: [ForecastHour] { rows.filter { $0.end > .now } }
    /// The good periods that haven't ended yet.
    var upcomingGood: [Period] { good.filter { $0.end > .now } }
}

enum Compass {
    static let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
}

/// Asks Kookout's relay to work out a spot: it fetches MET's forecast (and waves for surf spots)
/// and applies the same rules as the web page (rules.js).
enum KookoutAPI {
    static let relay = URL(string: "https://wingfoil-relay.wingfoil-relay.workers.dev")!

    /// `units` ("ms"/"kn") and `waveUnit` ("m"/"ft") decide how the rules round, like on the web page.
    static func analyse(_ spot: Spot, units: String, waveUnit: String) async throws -> SpotForecast {
        var request = URLRequest(url: relay.appending(path: "analyse"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnalyseRequest(spot: .init(spot), units: units, waveUnit: waveUnit))
        request.timeoutInterval = 40 // the first wave forecast for a new place can be slow

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decoder.decode(SpotForecast.self, from: data)
    }

    // The spot's values are always m/s and metres; the units only decide rounding (and are shown in the app).
    private struct AnalyseRequest: Encodable {
        let spot: RelaySpot
        let units: String
        let waveUnit: String
    }

    private struct RelaySpot: Encodable {
        let lat: Double, lon: Double, alt: Double?, tz: String
        let wind: WindRule?, surf: SurfRule?, powder: PowderRule?
        init(_ s: Spot) {
            lat = s.latitude; lon = s.longitude; alt = s.altitude; tz = s.timeZoneID
            wind = s.wind; surf = s.surf; powder = s.powder
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // The relay sends times like "2026-10-13T10:00:00.000Z" (with or without the fraction).
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()
}
