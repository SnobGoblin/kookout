import SwiftUI
import WidgetKit

// Kookout's widget: the spots that are good soonest, on the home screen and the Lock Screen.
// The app writes the spots and settings into the App Group (WidgetBridge); the widget asks the relay about once an hour
// which are good and when (POST /widget, the same rules as the app), and falls back on the last known answer offline.

@main
struct KookoutWidgets: WidgetBundle {
    var body: some Widget { SpotsWidget() }
}

struct SpotsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetData.kind, provider: Provider()) { entry in
            SpotsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        }
        .configurationDisplayName(Text(verbatim: "Kookout"))
        .description("Your spots that are good soonest.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Data

struct Entry: TimelineEntry {
    let date: Date
    /// Nil: the app hasn't told the widget about any spots yet.
    let spots: WidgetSpots?
    let statuses: [WidgetStatus]

    init(date: Date, spots: WidgetSpots?, known: WidgetPeriods) {
        self.date = date
        self.spots = spots
        statuses = WidgetStatus.soonest(spots?.spots ?? [], known, at: date)
    }

    /// For the widget gallery before the app has any spots: three made-up ones.
    static var sample: Entry {
        let now = Date.now, hour = 3600.0
        let spot = { (id: String, name: String) in WidgetSpots.Spot(id: id, name: name, sport: "wing", tz: TimeZone.current.identifier) }
        let spots = WidgetSpots(spots: [spot("a", "Torkild"), spot("b", "Larkollen"), spot("c", "Møvik")],
                                units: "ms", waveUnit: "m", h12: false, request: Data())
        let known = WidgetPeriods(periods: [
            "a": [WidgetPeriod(start: now - hour, end: now + 3 * hour, lo: 9, hi: 14)],
            "b": [WidgetPeriod(start: now + 50 * hour, end: now + 54 * hour, lo: 7, hi: 11)],
            "c": []])
        return Entry(date: now, spots: spots, known: known)
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { .sample }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) {
        let spots = WidgetData.load(WidgetSpots.self, WidgetSpots.file)
        guard let spots, !spots.spots.isEmpty else { return completion(.sample) }
        completion(Entry(date: .now, spots: spots, known: WidgetData.load(WidgetPeriods.self, WidgetPeriods.file) ?? .init()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        Task { completion(await Self.timeline()) }
    }

    /// Ask the relay (or use the last answer), then one entry now and one each time a good period starts or ends in
    /// the next hours; asked again in about an hour, or sooner when the app changes the spots.
    static func timeline() async -> Timeline<Entry> {
        let spots = WidgetData.load(WidgetSpots.self, WidgetSpots.file)
        var known = WidgetData.load(WidgetPeriods.self, WidgetPeriods.file) ?? WidgetPeriods()
        if let spots, !spots.spots.isEmpty, let fresh = await fetch(spots) {
            for (id, periods) in fresh { known.periods[id] = periods }
            known.periods = known.periods.filter { id, _ in spots.spots.contains { $0.id == id } }
            WidgetData.save(known, WidgetPeriods.file)
        }
        let now = Date.now
        let dates = [now] + WidgetStatus.changes(known, from: now, until: now + 6 * 3600).prefix(12)
        return Timeline(entries: dates.map { Entry(date: $0, spots: spots, known: known) },
                        policy: .after(now + 3600))
    }

    /// The relay's answer, by spot id; spots it couldn't work out are left out (they keep what was known).
    static func fetch(_ spots: WidgetSpots) async -> [String: [WidgetPeriod]]? {
        var request = URLRequest(url: WidgetData.relay.appending(path: "widget"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = spots.request
        request.timeoutInterval = 20
        struct Answer: Decodable { struct Spot: Decodable { let periods: [WidgetPeriod]? }; let spots: [Spot] }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? WidgetData.decoder.decode(Answer.self, from: data),
              answer.spots.count == spots.spots.count else { return nil }
        var result: [String: [WidgetPeriod]] = [:]
        for (spot, a) in zip(spots.spots, answer.spots) { if let periods = a.periods { result[spot.id] = periods } }
        return result
    }
}

// MARK: - Texts

/// How a spot's status is written, in the units and clock the app uses.
struct Words {
    let spots: WidgetSpots?
    let now: Date

    func powder(_ s: WidgetStatus) -> Bool { s.spot.sport == "powder" }

    /// "Good now", "Next good", "Powder today", "Nothing good in sight"…
    func title(_ s: WidgetStatus) -> String {
        guard s.known else { return String(localized: "No forecast yet") }
        guard s.period != nil else { return String(localized: "Nothing good in sight") }
        if powder(s) { return s.goodNow ? String(localized: "Powder today") : String(localized: "Next powder") }
        return s.goodNow ? String(localized: "Good now") : String(localized: "Next good")
    }

    /// Good now: the wind or waves ("9–14 m/s", "1.2 m"). Later: when ("Sat 10–15", powder "Sat").
    func detail(_ s: WidgetStatus) -> String? {
        guard let p = s.period else { return nil }
        if !s.goodNow { return (powder(s) ? day(p.start, s) : "\(day(p.start, s)) \(hours(p, s))").capitalizedFirst }
        if s.spot.sport == "surf", let wave = p.wave { return "\(waves(wave)) \(spots?.waveUnit == "ft" ? "ft" : "m")" }
        guard let lo = p.lo, let hi = p.hi else { return nil }
        let (a, b) = (wind(lo), wind(hi))
        return "\(a == b ? "\(a)" : "\(a)–\(b)") \(spots?.units == "kn" ? String(localized: "kn") : "m/s")"
    }

    /// One short line for the medium widget: "Now · 9–14 m/s", "Sat 10–15", "–".
    func line(_ s: WidgetStatus) -> String {
        guard let p = s.period else { return "–" }
        if s.goodNow { return [String(localized: "now"), detail(s)].compactMap { $0 }.joined(separator: " · ").capitalizedFirst }
        return (powder(s) ? day(p.start, s) : "\(day(p.start, s)) \(hours(p, s))").capitalizedFirst
    }

    /// Good now (not powder): "until 18" / "until 6 PM".
    func until(_ s: WidgetStatus) -> String? {
        guard s.goodNow, !powder(s), let p = s.period else { return nil }
        return String(localized: "until \(hour(p.end, s))")
    }

    /// Shortest, for the Lock Screen: "now", today's hours ("14–18"), or just the weekday ("Thu"; a weekday with an
    /// hour, "Thu 07", read like a date). "–" when nothing is good.
    func short(_ s: WidgetStatus) -> String {
        guard let p = s.period else { return "–" }
        if s.goodNow { return String(localized: "now") }
        if isToday(p.start, s) && !powder(s) { return hours(p, s) }
        return weekday(p.start, s)
    }

    /// One line beside the clock: "Torkild good 14–18", "Torkild good Sat 10–15", "Hemsedal powder Sat".
    func inline(_ s: WidgetStatus) -> String {
        guard let p = s.period else { return String(localized: "Nothing good in sight") }
        let name = s.spot.name
        if powder(s) { return String(localized: "\(name) powder \(day(p.start, s))") }
        let when = s.goodNow || isToday(p.start, s) ? hours(p, s) : "\(day(p.start, s)) \(hours(p, s))"
        return String(localized: "\(name) good \(when)")
    }

    // Times are in the spot's own time zone, like in the app.
    private func zone(_ s: WidgetStatus) -> TimeZone { TimeZone(identifier: s.spot.tz) ?? .current }
    private func calendar(_ s: WidgetStatus) -> Calendar { var c = Calendar.current; c.timeZone = zone(s); return c }
    private func isToday(_ date: Date, _ s: WidgetStatus) -> Bool { calendar(s).isDate(date, inSameDayAs: now) }

    /// "today", "tomorrow" or the weekday ("Thu").
    func day(_ date: Date, _ s: WidgetStatus) -> String {
        if isToday(date, s) { return String(localized: "today") }
        if calendar(s).isDate(date, inSameDayAs: now + 86400) { return String(localized: "tomorrow") }
        return weekday(date, s)
    }
    /// A week or more ahead the weekday alone would read as this week's: the date instead ("11 Nov").
    func weekday(_ date: Date, _ s: WidgetStatus) -> String {
        let c = calendar(s)
        let days = c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: date)).day ?? 0
        var style = days >= 7 ? Date.FormatStyle.dateTime.day().month(.abbreviated) : Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = zone(s)
        return date.formatted(style)
    }

    /// "10–15", or with a 12-hour clock "10 AM–3 PM" / "3–6 PM".
    func hours(_ p: WidgetPeriod, _ s: WidgetStatus) -> String {
        guard spots?.h12 == true else { return "\(format(p.start, s, "HH"))–\(format(p.end, s, "HH"))" }
        return format(p.start, s, "a") == format(p.end, s, "a")
            ? "\(format(p.start, s, "h"))–\(format(p.end, s, "h a"))"
            : "\(format(p.start, s, "h a"))–\(format(p.end, s, "h a"))"
    }
    /// "12" or "12 PM".
    func hour(_ date: Date, _ s: WidgetStatus) -> String { format(date, s, spots?.h12 == true ? "h a" : "HH") }

    private func format(_ date: Date, _ s: WidgetStatus, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = pattern
        f.timeZone = zone(s)
        return f.string(from: date)
    }

    // Rounded like the app shows them (and judges them).
    private func wind(_ ms: Double) -> Int { Int((spots?.units == "kn" ? ms * 1.94384 : ms).rounded()) }
    private func waves(_ m: Double) -> String {
        spots?.waveUnit == "ft" ? String(Int((m * 3.28084).rounded())) : m.formatted(.number.precision(.fractionLength(1)))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Views

struct SpotsWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var words: Words { Words(spots: entry.spots, now: entry.date) }
    private var anyGood: Bool { entry.statuses.contains { $0.period != nil } }

    var body: some View {
        if entry.statuses.isEmpty {
            empty
        } else {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    /// No spots yet (or the app hasn't been opened since it got the widget).
    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); Image(systemName: "wind").font(.title2) }
        case .accessoryInline:
            Text("Add your spots in Kookout")
        default:
            VStack(alignment: .leading, spacing: 4) {
                if family != .accessoryRectangular { Image(systemName: "wind").font(.title2).foregroundStyle(Color.kookout) }
                Text("Add your spots in Kookout").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// Like the app's list: green when something good is coming, the accent colour when nothing is.
    private func iconColor(_ s: WidgetStatus) -> Color { s.period != nil ? .green : .kookout }

    // Home screen, small: the soonest spot.
    private var small: some View {
        let s = entry.statuses[0]
        return VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol(s)).font(.title3).foregroundStyle(iconColor(s))
            Text(s.spot.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(words.title(s)).font(.subheadline.weight(.semibold))
                .foregroundStyle(s.goodNow ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .lineLimit(2).minimumScaleFactor(0.8)
            if let detail = words.detail(s) {
                Text(detail).font(.subheadline).lineLimit(1).minimumScaleFactor(0.7)
            }
            if let until = words.until(s) {
                Text(until).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(WidgetData.link(s.spot.id))
    }

    // Home screen, medium: three spots, one line each; tapping a line opens that spot.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "Kookout").font(.caption.weight(.semibold)).foregroundStyle(Color.kookout)
                Spacer()
                if !anyGood { Text("Nothing good in sight").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            ForEach(entry.statuses, id: \.spot.id) { s in
                Spacer(minLength: 0)
                Link(destination: WidgetData.link(s.spot.id)) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(s)).foregroundStyle(iconColor(s))
                            .frame(width: 22)
                        Text(s.spot.name).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(words.line(s)).lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(s.goodNow ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            .fontWeight(s.goodNow ? .semibold : .regular)
                            .layoutPriority(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // Lock Screen, rectangular: three short lines, the name and when. One colour only there, so "now" is in bold.
    private var rectangular: some View {
        // All lines at one size: the largest where every line fits, and only then shortened names
        // ("Hvide Sande, fjo… now"); the time always shows in full.
        ViewThatFits(in: .horizontal) {
            lockLines(font: .body, fit: true)
            lockLines(font: .footnote, fit: true)
            lockLines(font: .footnote, fit: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetData.link(entry.statuses[0].spot.id))
    }

    private func lockLines(font: Font, fit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !anyGood { Text("Nothing good in sight").font(.headline).lineLimit(1).minimumScaleFactor(0.7) }
            ForEach(entry.statuses.prefix(anyGood ? 3 : 2), id: \.spot.id) { s in
                lockLine(s, font: font, fit: fit)
                    .fontWeight(s.goodNow ? .semibold : .regular)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(s.spot.name), \(words.title(s)) \(words.detail(s) ?? "")"))
            }
        }
    }

    private func lockLine(_ s: WidgetStatus, font: Font, fit: Bool) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: s.spot.name)
                .lineLimit(1)
                .fixedSize(horizontal: fit, vertical: false)
            Text(verbatim: words.short(s)).lineLimit(1).fixedSize()
        }
        .font(font)
    }

    // Lock Screen, circular: the soonest spot; a tick when it's good now, otherwise today's hours or the weekday.
    private var circular: some View {
        let s = entry.statuses[0]
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbol(s)).font(.caption)
                if s.goodNow {
                    Image(systemName: "checkmark").font(.title3.bold())
                } else if let p = s.period {
                    // Today: the hours ("14–18"); another day: just the weekday, like the rectangular one.
                    Text(words.short(s)).font(.headline).lineLimit(1).minimumScaleFactor(0.5)
                } else {
                    Text(verbatim: "–").font(.title3.bold())
                }
            }
            .padding(2)
        }
        .widgetURL(WidgetData.link(s.spot.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(s.spot.name), \(words.title(s)) \(words.detail(s) ?? "")"))
    }

    // Lock Screen, one line above the clock.
    private var inline: some View {
        let s = entry.statuses[0]
        return Text(words.inline(s)).widgetURL(WidgetData.link(s.spot.id))
    }

    private func symbol(_ s: WidgetStatus) -> String {
        switch s.spot.sport {
        case "surf": "water.waves"
        case "powder": "snowflake"
        default: "wind"
        }
    }
}

#Preview(as: .systemSmall) { SpotsWidget() } timeline: { Entry.sample }
#Preview(as: .systemMedium) { SpotsWidget() } timeline: { Entry.sample }
#Preview(as: .accessoryRectangular) { SpotsWidget() } timeline: { Entry.sample }

extension Color {
    /// Kookout's accent: sea blue, buoy orange in dark mode (Assets.xcassets; widgets don't pick up the accent by themselves).
    static let kookout = Color("AccentColor")
}
