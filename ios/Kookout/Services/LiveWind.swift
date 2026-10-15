import Foundation

/// The wind measured right now near a spot (relay /near and /obs: MET's Frost, Kystverket, NOAA), like the web
/// page's "Nå:" line. The person can pick the station (Edit); Holfuy stations are shown with Holfuy's widget.
struct LiveWind: Decodable, Hashable {
    let name: String
    let wind: Double        // m/s
    let gust: Double?
    let dir: Double?        // degrees, where it comes from
    let km: Double
    let time: Date

    /// A station that can be picked for a spot.
    struct Station: Identifiable, Hashable {
        let id: String       // "SN17280", "KV:12735059", "holfuy:1815"
        let name: String
        let km: Double
        let reading: LiveWind?   // nil for Holfuy (their readings are only in their widget)
        var isHolfuy: Bool { id.hasPrefix("holfuy:") }
        var holfuyNumber: String? { isHolfuy ? String(id.dropFirst(7)) : nil }
    }

    private struct Answer: Decodable {
        let stations: [Row]
        let holfuy: [Holfuy]?
    }
    private struct Row: Decodable {
        let id: String?, name: String?, wind: Double?, gust: Double?, dir: Double?, km: Double?, time: String?
    }
    private struct Holfuy: Decodable { let holfuy: Int; let name: String?; let km: Double? }

    /// Every station within 50 km of the spot: official ones (with their latest reading) and Holfuy's.
    static func stations(near spot: Spot) async -> [Station] {
        var c = URLComponents(url: KookoutAPI.relay.appending(path: "near"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "lat", value: String(spot.latitude)), .init(name: "lon", value: String(spot.longitude))]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return [] }
        let official = answer.stations.compactMap { s -> Station? in
            guard let id = s.id, let km = s.km else { return nil }
            var reading: LiveWind?
            if let wind = s.wind, let time = s.time.flatMap(Community.date) {
                reading = LiveWind(name: s.name ?? id, wind: wind, gust: s.gust, dir: s.dir, km: km, time: time)
            }
            return Station(id: id, name: s.name ?? id, km: km, reading: reading)
        }
        let holfuy = (answer.holfuy ?? []).map { Station(id: "holfuy:\($0.holfuy)", name: $0.name ?? "Holfuy \($0.holfuy)",
                                                       km: $0.km ?? 0, reading: nil) }
        return (official + holfuy).sorted { $0.km < $1.km }
    }

    /// What to show for a spot: the person's station, else the one most riders chose (the community's), else the
    /// nearest official one within 30 km with a reading from the last 90 minutes. A Holfuy station comes back without a
    /// reading (the app shows the widget).
    /// The last answer for each spot while the app runs, so its screen can show it at once and update it in place.
    @MainActor static var latest: [String: Station?] = [:]

    static func now(for spot: Spot) async -> Station? {
        let all = await stations(near: spot)
        let fresh = { (s: Station) in s.reading.map { Date.now.timeIntervalSince($0.time) < 90 * 60 } ?? false }
        if let id = spot.station ?? spot.community?.station,
           let chosen = all.first(where: { $0.id == id }) { return chosen } // even if it's late
        return all.first { !$0.isHolfuy && $0.km <= 30 && fresh($0) }
    }
}
