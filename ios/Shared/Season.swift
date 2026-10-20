import Foundation

/// The part of the year a spot gives notifications and counts in the widget (relay/src/season.js). Outside it the
/// forecast still shows, but nothing is good. Both days are included; `from` after `to` goes over New Year.
struct Season: Codable, Hashable {
    var from: String    // "MM-DD"
    var to: String

    static let allYear = Season(from: "01-01", to: "12-31")
    /// Wing and surf in the north (about 50° N and up): mid-March to Christmas Eve.
    static let north = Season(from: "03-15", to: "12-24")

    /// What a spot gets before its followers vote: `north` for wing and surf from 50° N, otherwise all year (powder's
    /// rule only fires in winter anyway). The same as defaultSeason in the relay.
    static func standard(latitude: Double, sport: String) -> Season {
        sport != "powder" && latitude >= 50 ? north : allYear
    }

    init(from: String, to: String) { self.from = from; self.to = to }
    init(from: (month: Int, day: Int), to: (month: Int, day: Int)) {
        self.from = Self.key(from.month, from.day); self.to = Self.key(to.month, to.day)
    }

    var isAllYear: Bool { self == .allYear || Self.next(to) == from }

    func contains(_ date: Date, zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.month, .day], from: date)
        return contains(Self.key(c.month ?? 1, c.day ?? 1))
    }

    private func contains(_ day: String) -> Bool {
        from <= to ? day >= from && day <= to : day >= from || day <= to
    }

    var start: (month: Int, day: Int) { Self.parts(from) }
    var end: (month: Int, day: Int) { Self.parts(to) }

    static let daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    private static func key(_ month: Int, _ day: Int) -> String { String(format: "%02d-%02d", month, day) }
    private static func parts(_ key: String) -> (month: Int, day: Int) {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : (1, 1)
    }
    /// The day after ("12-31" → "01-01").
    private static func next(_ key: String) -> String {
        let (m, d) = parts(key)
        return d < daysInMonth[m - 1] ? Self.key(m, d + 1) : Self.key(m % 12 + 1, 1)
    }
}
