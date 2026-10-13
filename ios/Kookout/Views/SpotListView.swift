import SwiftUI

struct SpotListView: View {
    @Environment(SpotStore.self) private var store
    @State private var showSettings = false
    @State private var showAdd = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                ForEach(store.spots) { spot in
                    NavigationLink(value: spot) {
                        SpotRow(spot: spot, forecast: store.forecasts[spot.id], failed: store.failed.contains(spot.id))
                    }
                }
                .onDelete { store.spots.remove(atOffsets: $0) }
                .onMove { store.spots.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if store.spots.isEmpty {
                    ContentUnavailableView("No spots yet", systemImage: "mappin.and.ellipse",
                                           description: Text("Tap + to add your first spot."))
                }
            }
            .navigationTitle("Kookout")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add spot")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAdd) { AddSpotView() }
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
            .task { await store.refreshAll() }
            .refreshable { await store.refreshAll() }
        }
    }
}

/// A spot in the list, with the next good session if there is one: "Good Thu 10–14".
struct SpotRow: View {
    let spot: Spot
    let forecast: SpotForecast?
    let failed: Bool

    var body: some View {
        HStack {
            Image(systemName: spot.sport.symbol)
                .foregroundStyle(next != nil ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                if let next {
                    Text(next).font(.caption).foregroundStyle(.green)
                } else if failed {
                    Text("Couldn't load the forecast").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if forecast == nil && !failed { ProgressView() }
        }
    }

    /// The first good period, in the spot's own time, e.g. "Good Thu 10–14" or "Powder Sat".
    private var next: String? {
        guard let forecast else { return nil }
        let zone = spot.timeZone
        if let first = forecast.good.first {
            let day = Self.dayLabel(first.start, zone: zone)
            let hours = "\(first.start.hourText(in: zone))–\(first.end.hourText(in: zone))"
            return String(localized: "Good \(day) \(hours)")
        }
        if let firstPowder = forecast.powderDays.first, let date = Self.dayFormatter.date(from: firstPowder) {
            return String(localized: "Powder \(Self.dayLabel(date, zone: .gmt))")
        }
        return nil
    }

    static func dayLabel(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = zone
        if calendar.isDateInToday(date) { return String(localized: "today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "tomorrow") }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = zone
        return date.formatted(style)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .gmt
        return f
    }()
}

extension Date {
    /// The bare two-digit hour in a time zone, e.g. "14", the same in every language
    /// (a plain date format would say "14 Uhr" in German). Used for ranges like "10–14".
    func hourText(in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        formatter.timeZone = zone
        return formatter.string(from: self)
    }
}

extension Sport {
    /// SF Symbols for the sports (placeholders until the app has its own icons).
    var symbol: String {
        switch self {
        case .wing: "wind"
        case .surf: "water.waves"
        case .powder: "snowflake"
        }
    }
}

#Preview {
    SpotListView().environment(SpotStore())
}
