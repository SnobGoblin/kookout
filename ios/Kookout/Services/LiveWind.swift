import Foundation

/// The wind measured right now at the nearest official station (relay /near: MET's Frost, Kystverket, NOAA),
/// like the web page's "Nå:" line.
struct LiveWind: Decodable, Hashable {
    let name: String
    let wind: Double        // m/s
    let gust: Double?
    let dir: Double?        // degrees, where it comes from
    let km: Double
    let time: Date

    private struct Answer: Decodable { let stations: [Station] }
    private struct Station: Decodable {
        let name: String?, wind: Double?, gust: Double?, dir: Double?, km: Double?, time: String?
    }

    /// The nearest station within 30 km with a reading from the last 90 minutes.
    static func near(_ spot: Spot) async -> LiveWind? {
        var c = URLComponents(url: KookoutAPI.relay.appending(path: "near"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "lat", value: String(spot.latitude)), .init(name: "lon", value: String(spot.longitude))]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        for s in answer.stations {
            guard let wind = s.wind, let km = s.km, km <= 30, let time = s.time.flatMap(Community.date),
                  Date.now.timeIntervalSince(time) < 90 * 60 else { continue }
            return LiveWind(name: s.name ?? "", wind: wind, gust: s.gust, dir: s.dir, km: km, time: time)
        }
        return nil
    }
}
