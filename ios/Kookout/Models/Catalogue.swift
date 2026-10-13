import Foundation
import CoreLocation

/// Popular spots built into the app (Catalogue.json), so new users have something to start with before
/// anyone has added their own. Each comes with the standard rules for its sport and the wind directions
/// that usually work there.
enum Catalogue {
    struct Entry {
        let spot: Spot
        let area: String
        var location: CLLocation { CLLocation(latitude: spot.latitude, longitude: spot.longitude) }
    }

    static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "Catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.map(\.entry)
    }()

    /// The catalogue spots nearest to a place, nearest first, leaving out the ones the user already has.
    static func nearest(to location: CLLocation, excluding ids: Set<String> = [], count: Int = 5) -> [(entry: Entry, meters: Double)] {
        entries.filter { !ids.contains($0.spot.id) }
            .map { ($0, $0.location.distance(from: location)) }
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map { (entry: $0.0, meters: $0.1) }
    }

    /// One spot as written in Catalogue.json.
    private struct Row: Decodable {
        let id, name, area, tz, sport: String
        let lat, lon: Double
        let dirs: [String]?
        let sunny: [Double]?
        let altitude: Double?

        var entry: Entry {
            var spot = Spot(id: id, name: name, latitude: lat, longitude: lon, altitude: altitude, timeZoneID: tz)
            switch sport {
            case "surf": spot.surf = SurfRule(dirs: dirs ?? Compass.points)
            case "powder": spot.powder = PowderRule()
            default:
                let sunnyLimits = sunny.flatMap { $0.count == 3 ? WindRule.Limits(min: $0[0], gust: $0[1], steady: $0[2]) : nil }
                spot.wind = WindRule(dirs: dirs ?? Compass.points, sunny: sunnyLimits)
            }
            return Entry(spot: spot, area: area)
        }
    }
}

/// The phone's location, once, asking for permission if needed. Nil if not allowed or not found in time.
@MainActor
enum Locator {
    static func current() async -> CLLocation? {
        let manager = CLLocationManager()
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { return nil }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        let found = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                        if #available(iOS 18, *), update.authorizationDenied { return nil }
                    }
                } catch {}
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(20)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        withExtendedLifetime(manager) {} // keep the manager (and its permission question) alive until here
        return found
    }
}

extension Measurement where UnitType == UnitLength {
    /// "12 km" or "8 mi", as the phone's region prefers.
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
