import Foundation

/// One step of the forecast: an hour (or, further ahead, six hours).
struct ForecastHour: Identifiable, Hashable {
    var id: Date { time }
    let time: Date
    let hours: Int
    let symbol: String?
    let temperature: Double
    let precipitation: Double
    let wind: Double          // m/s
    let gust: Double?         // m/s, only given in the hourly part
    let windFrom: Double      // degrees, where the wind comes from

    var compass: String { Compass.name(for: windFrom) }
}

enum Compass {
    static let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    static func name(for degrees: Double) -> String {
        points[Int((degrees / 22.5).rounded()) % 16]
    }
}

/// Fetches MET Norway's Locationforecast (the same data as yr.no), about a week ahead.
enum ForecastService {
    // MET asks every app to identify itself with a way to contact the developer.
    private static let userAgent = "Kookout/0.1 (kookout.no, hi@kookout.no)"

    static func forecast(for spot: Spot) async throws -> [ForecastHour] {
        var url = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/complete")!
        url.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", spot.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.4f", spot.longitude)),
        ]
        var request = URLRequest(url: url.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder.met.decode(METResponse.self, from: data)

        // Hourly steps first (about 2½ days), then the 6-hour steps up to a week ahead, like the web page.
        let series = decoded.properties.timeseries
        let hourly = series.filter { $0.data.next_1_hours != nil }
        let lastHourly = hourly.last?.time ?? .distantPast
        let weekAhead = Date().addingTimeInterval(7 * 24 * 3600)
        let sixHourly = series.filter { $0.time > lastHourly && $0.data.next_6_hours != nil && $0.time < weekAhead }

        return hourly.map { $0.hour(step: 1) } + sixHourly.map { $0.hour(step: 6) }
    }
}

// MARK: - MET's JSON format (only the parts we use)

private struct METResponse: Decodable {
    let properties: Properties
    struct Properties: Decodable { let timeseries: [Step] }
}

private struct Step: Decodable {
    let time: Date
    let data: StepData

    struct StepData: Decodable {
        let instant: Instant
        let next_1_hours: Period?
        let next_6_hours: Period?
    }
    struct Instant: Decodable { let details: Details }
    struct Details: Decodable {
        let air_temperature: Double
        let wind_speed: Double
        let wind_from_direction: Double
        let wind_speed_of_gust: Double?
    }
    struct Period: Decodable {
        let summary: Summary
        let details: PeriodDetails
    }
    struct Summary: Decodable { let symbol_code: String }
    struct PeriodDetails: Decodable { let precipitation_amount: Double? }

    func hour(step: Int) -> ForecastHour {
        let period = step == 1 ? data.next_1_hours : data.next_6_hours
        let d = data.instant.details
        return ForecastHour(time: time, hours: step, symbol: period?.summary.symbol_code,
                            temperature: d.air_temperature, precipitation: period?.details.precipitation_amount ?? 0,
                            wind: d.wind_speed, gust: d.wind_speed_of_gust, windFrom: d.wind_from_direction)
    }
}

private extension JSONDecoder {
    static let met: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
