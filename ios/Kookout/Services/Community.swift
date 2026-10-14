import Foundation

/// Community spots (relay/src/community.js): spots someone shared, and the app's built-in ones. The phone follows the
/// community spots in its list; their name and position come from the community (anyone signed in can fix them, and
/// every change is logged), while the rules are the follower's own or, if they never changed them, the community's.
@MainActor
enum Community {
    /// A spot's rules for its sport, to compare the follower's version with the community's.
    struct Rules: Codable, Hashable {
        var wind: WindRule?
        var surf: SurfRule?
        var powder: PowderRule?
        init(_ spot: Spot) { wind = spot.wind; surf = spot.surf; powder = spot.powder }
        init(sport: String, json: Data) {
            switch sport {
            case "surf": surf = try? JSONDecoder().decode(SurfRule.self, from: json)
            case "powder": powder = try? JSONDecoder().decode(PowderRule.self, from: json)
            default: wind = try? JSONDecoder().decode(WindRule.self, from: json)
            }
        }
        var isEmpty: Bool { wind == nil && surf == nil && powder == nil }
    }

    /// What the app knows about a community spot it follows.
    struct Info: Codable, Hashable {
        var rules: Rules            // the community's version
        var followers: Int
        var by: String?             // who first shared it
        var catalogue: Bool
        var lastEdit: Edit?
        struct Edit: Codable, Hashable { let field: String; let at: Date; let by: String? }
    }

    private static var pending: Task<Void, Never>?

    /// The list changed (or the app started): tell the relay which community spots this phone has, and take over
    /// the community's names, positions and (where untouched) rules. After a moment's calm.
    static func syncSoon(_ store: SpotStore) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync(store)
        }
    }

    static func sync(_ store: SpotStore) async {
        // Every spot except the private ones the user made: own shared spots, and ones from the map or the catalogue
        let candidates = store.spots.filter { $0.shared != false }
        let body: [String: Any] = ["key": SharedSpots.key, "spots": candidates.map { spot -> [String: Any] in
            // Their own version if it differs from the community's (and, the first time, whatever they have)
            let own = spot.community.map { Rules(spot) != $0.rules } ?? true
            return ["id": spot.id, "rule": own ? (ruleJSON(spot) ?? NSNull()) : NSNull()]
        }]
        guard let answer = await call("PUT", "following", body: body) as? [String: Any],
              let rows = answer["spots"] as? [[String: Any]] else { return }
        store.applyCommunity(rows.compactMap(Remote.init))
    }

    /// Fix the name or position for everyone. Nil when it worked, otherwise what went wrong.
    static func edit(_ spot: Spot, name: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
                     store: SpotStore) async -> String? {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let latitude, let longitude { body["lat"] = latitude; body["lon"] = longitude }
        return await change("spots/\(spot.id)", body: body, store: store)
    }

    /// Report a spot, or a change to it. Nil when it was sent, otherwise what went wrong.
    static func report(_ spot: Spot, edit: LogEntry?, reason: String, note: String) async -> String? {
        var body: [String: Any] = ["key": SharedSpots.key, "spot": spot.id, "reason": reason, "note": note]
        if let edit { body["edit"] = edit.id }
        var problem: String?
        guard await call("POST", "reports", body: body, problem: &problem) != nil else {
            return problem ?? String(localized: "Couldn't reach Kookout. Check the internet connection.")
        }
        return nil
    }

    static func undo(_ edit: LogEntry, store: SpotStore) async -> String? {
        await change("edits/\(edit.id)/undo", body: [:], store: store)
    }

    struct LogEntry: Identifiable, Hashable {
        let id: Int
        let field: String           // "created", "name" or "position"
        let at: Date
        let by: String?
        let old: Any?, new: Any?
        let undoes: Int?
        let undone: Bool
        static func == (a: LogEntry, b: LogEntry) -> Bool { a.id == b.id && a.undone == b.undone }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    static func history(_ spot: Spot) async -> [LogEntry]? {
        guard let answer = await call("GET", "spots/\(spot.id)/history") as? [String: Any],
              let rows = answer["edits"] as? [[String: Any]] else { return nil }
        return rows.compactMap { r in
            guard let id = r["id"] as? Int, let field = r["field"] as? String,
                  let at = (r["at"] as? String).flatMap(date) else { return nil }
            return LogEntry(id: id, field: field, at: at, by: r["by"] as? String, old: r["old"], new: r["new"],
                            undoes: r["undoes"] as? Int, undone: r["undone"] as? Bool ?? false)
        }
    }

    // MARK: -

    /// A community spot as the relay describes it.
    struct Remote {
        let id, name, tz, sport: String
        let lat, lon: Double
        let info: Info
        init?(_ r: [String: Any]) {
            guard let id = r["id"] as? String, let name = r["name"] as? String, let tz = r["tz"] as? String,
                  let sport = r["sport"] as? String, let lat = r["lat"] as? Double, let lon = r["lon"] as? Double,
                  let rule = r["rule"], let json = try? JSONSerialization.data(withJSONObject: rule) else { return nil }
            let rules = Rules(sport: sport, json: json)
            guard !rules.isEmpty else { return nil }
            var edit: Info.Edit?
            if let e = r["lastEdit"] as? [String: Any], let field = e["field"] as? String,
               let at = (e["at"] as? String).flatMap(Community.date) { edit = .init(field: field, at: at, by: e["by"] as? String) }
            self.id = id; self.name = name; self.tz = tz; self.sport = sport; self.lat = lat; self.lon = lon
            info = Info(rules: rules, followers: r["followers"] as? Int ?? 1, by: r["by"] as? String,
                        catalogue: r["catalogue"] as? Bool ?? false, lastEdit: edit)
        }
    }

    private static func change(_ path: String, body: [String: Any], store: SpotStore) async -> String? {
        guard Account.shared.signedIn else { return String(localized: "To change spots for everyone, sign in with Apple in Settings.") }
        var problem: String?
        guard let answer = await call("POST", path, body: body, problem: &problem) as? [String: Any],
              let spot = (answer["spot"] as? [String: Any]).flatMap(Remote.init) else {
            return problem ?? String(localized: "Couldn't reach Kookout. Check the internet connection.")
        }
        store.applyCommunity([spot], only: true)
        return nil
    }

    private static func call(_ method: String, _ path: String, body: [String: Any]? = nil) async -> Any? {
        var ignored: String?
        return await call(method, path, body: body, problem: &ignored)
    }

    private static func call(_ method: String, _ path: String, body: [String: Any]?, problem: inout String?) async -> Any? {
        var request = URLRequest(url: KookoutAPI.relay.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Account.shared.authorize(&request)
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        let json = try? JSONSerialization.jsonObject(with: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            problem = (json as? [String: Any])?["error"] as? String
            return nil
        }
        return json
    }

    private static func ruleJSON(_ spot: Spot) -> Any? {
        let data: Data? = if let w = spot.wind { try? JSONEncoder().encode(w) }
                          else if let s = spot.surf { try? JSONEncoder().encode(s) }
                          else if let p = spot.powder { try? JSONEncoder().encode(p) } else { nil }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    nonisolated static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
