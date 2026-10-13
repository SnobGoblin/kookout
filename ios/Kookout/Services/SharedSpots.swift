import Foundation
import CoreLocation

/// Spots people share with each other through Kookout's relay. A spot the user adds is shared unless they
/// switch it off (Edit), with the name they chose in Settings as "added by", if any. Nothing links a shared
/// spot to the phone's notifications: the relay only knows a hash of a random key kept here, which lets this
/// phone (and only this phone) change or remove its shared spots.
@MainActor
enum SharedSpots {
    /// A spot someone shared, as the relay returns it.
    struct Shared: Identifiable {
        let spot: Spot
        let by: String?
        var id: String { spot.id }
        var location: CLLocation { CLLocation(latitude: spot.latitude, longitude: spot.longitude) }
    }

    private static let key: String = {
        if let key = UserDefaults.standard.string(forKey: "shareKey") { return key }
        let key = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined().lowercased()
        UserDefaults.standard.set(key, forKey: "shareKey")
        return key
    }()

    private static var spots: [Spot] = []

    /// The list changed: share new and edited spots, stop sharing removed or switched-off ones.
    static func sync(old: [Spot], new: [Spot]) {
        spots = new
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Set(new.map(\.id))
        for spot in new where spot.shared == true && before[spot.id] != spot { Task { await put(spot) } }
        for spot in old where spot.shared == true && (!after.contains(spot.id) || new.first { $0.id == spot.id }?.shared == false) {
            Task { await delete(spot.id) }
        }
    }

    /// The user's name changed: update "added by" on everything they share.
    static func nameChanged() {
        for spot in spots where spot.shared == true { Task { await put(spot) } }
    }

    /// Shared spots within about 300 km of a place, nearest first.
    static func near(_ location: CLLocation) async -> [Shared] {
        var components = URLComponents(url: KookoutAPI.relay.appending(path: "shared"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "lat", value: String(format: "%.2f", location.coordinate.latitude)),
                                 .init(name: "lon", value: String(format: "%.2f", location.coordinate.longitude))]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return [] }
        return answer.spots.compactMap(\.shared)
    }

    private static func put(_ spot: Spot) async {
        let body = Body(key: key, name: spot.name, by: Settings.shared.sharingName.isEmpty ? nil : Settings.shared.sharingName,
                        lat: spot.latitude, lon: spot.longitude, alt: spot.altitude, tz: spot.timeZoneID,
                        sport: spot.sport.rawValue, rule: Rule(spot))
        await send("PUT", spot.id, try? JSONEncoder().encode(body))
    }

    private static func delete(_ id: String) async {
        await send("DELETE", id, try? JSONEncoder().encode(["key": key]))
    }

    private static func send(_ method: String, _ id: String, _ body: Data?) async {
        var request = URLRequest(url: KookoutAPI.relay.appending(path: "shared").appending(path: id))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    private struct Body: Encodable {
        let key, name: String
        let by: String?
        let lat, lon: Double
        let alt: Double?
        let tz, sport: String
        let rule: Rule
    }

    /// The spot's rule for its sport, which is all the relay keeps of the rules.
    private struct Rule: Encodable {
        let spot: Spot
        init(_ spot: Spot) { self.spot = spot }
        func encode(to encoder: Encoder) throws {
            if let wind = spot.wind { try wind.encode(to: encoder) }
            else if let surf = spot.surf { try surf.encode(to: encoder) }
            else if let powder = spot.powder { try powder.encode(to: encoder) }
        }
    }

    private struct Answer: Decodable { let spots: [Row] }

    /// One shared spot; nil if its rule can't be read (the relay accepts what any app sends).
    private struct Row: Decodable {
        let shared: Shared?
        enum Keys: String, CodingKey { case id, name, by, lat, lon, alt, tz, sport, rule }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            guard let id = try? c.decode(String.self, forKey: .id), let name = try? c.decode(String.self, forKey: .name),
                  let lat = try? c.decode(Double.self, forKey: .lat), let lon = try? c.decode(Double.self, forKey: .lon),
                  let tz = try? c.decode(String.self, forKey: .tz), let sport = try? c.decode(String.self, forKey: .sport)
            else { shared = nil; return }
            var spot = Spot(id: id, name: name, latitude: lat, longitude: lon,
                            altitude: try? c.decode(Double.self, forKey: .alt), timeZoneID: tz)
            switch sport {
            case "wing": spot.wind = try? c.decode(WindRule.self, forKey: .rule)
            case "surf": spot.surf = try? c.decode(SurfRule.self, forKey: .rule)
            case "powder": spot.powder = try? c.decode(PowderRule.self, forKey: .rule)
            default: break
            }
            guard spot.wind != nil || spot.surf != nil || spot.powder != nil else { shared = nil; return }
            let by = try? c.decode(String.self, forKey: .by)
            spot.addedBy = by
            shared = Shared(spot: spot, by: by)
        }
    }
}
