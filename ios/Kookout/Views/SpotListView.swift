import SwiftUI
import CoreLocation

struct SpotListView: View {
    @Environment(SpotStore.self) private var store
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var path: [Route] = []
    @State private var locating = false
    @State private var pickNear: CLLocation?

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            List {
                ForEach(store.spots) { spot in
                    NavigationLink(value: Route.detail(spot)) {
                        SpotRow(spot: spot, forecast: store.forecasts[spot.id], failed: store.failed.contains(spot.id))
                    }
                }
                .onDelete { store.spots.remove(atOffsets: $0) }
                .onMove { store.spots.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if store.spots.isEmpty { welcome }
            }
            .navigationTitle("Kookout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.spots.isEmpty { ToolbarItem(placement: .topBarLeading) { EditButton() } }
                ToolbarItem(placement: .principal) {
                    Image("Wordmark") // KOOKOUT with the O's looking out (brand/)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 17)
                        .accessibilityLabel("Kookout")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add spot")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $pickNear) { here in
                NearbyPicker(location: here) { showAdd = true }
            }
            // A new spot opens straight in its settings (directions and limits); Back goes to its forecast.
            .sheet(isPresented: $showAdd) { AddSpotView { spot in path = [.detail(spot), .edit(spot)] } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail(let spot): SpotDetailView(spot: spot)
                case .edit(let spot): SpotEditView(spot: spot)
                }
            }
            .task { await store.refreshAll() }
            // A tapped notification opens its spot.
            .onChange(of: Notifications.shared.openSpotID) {
                guard let id = Notifications.shared.openSpotID, let spot = store.spots.first(where: { $0.id == id }) else { return }
                path = [.detail(spot)]
                Notifications.shared.openSpotID = nil
            }
            .refreshable { await store.refreshAll() }
        }
    }
}

extension SpotListView {
    /// A new install (or after "Remove all spots"): start with the popular spots nearby, or add your own.
    var welcome: some View {
        ContentUnavailableView {
            Label("Welcome to Kookout", systemImage: "wind")
        } description: {
            Text(locating ? "Finding spots near you…" : "Start with popular spots near you, or add your own.")
        } actions: {
            Button("Spots near me") {
                Task {
                    locating = true
                    if let here = await Locator.current() { pickNear = here } else { showAdd = true }
                    locating = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(locating)
            Button("Add a spot on the map") { showAdd = true }
        }
    }
}

extension CLLocation: @retroactive Identifiable {
    public var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
}

/// The popular spots within 200 km, to pick from (for the welcome screen).
struct NearbyPicker: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let location: CLLocation
    /// "Add a spot on the map", for when there's nothing nearby.
    var addOwn: () -> Void
    @State private var picked: Set<String> = []

    private var nearby: [(entry: Catalogue.Entry, meters: Double)] {
        Catalogue.nearest(to: location, excluding: Set(store.spots.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List(nearby, id: \.entry.spot.id) { item in
                let spot = item.entry.spot
                Button {
                    if picked.contains(spot.id) { picked.remove(spot.id) } else { picked.insert(spot.id) }
                } label: {
                    HStack {
                        Image(systemName: spot.sport.symbol).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(spot.name)
                            Text("\(item.entry.area) · \(Measurement.distance(item.meters))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: picked.contains(spot.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(spot.id) ? Color.accentColor : .secondary)
                            .imageScale(.large)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityAddTraits(picked.contains(spot.id) ? .isSelected : [])
            }
            .overlay {
                if nearby.isEmpty {
                    ContentUnavailableView {
                        Label("No popular spots within 200 km", systemImage: "mappin.slash")
                    } description: {
                        Text("Add your own spot on the map instead.")
                    } actions: {
                        Button("Add a spot on the map") { dismiss(); addOwn() }
                    }
                }
            }
            .navigationTitle("Spots near you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(contentsOf: nearby.map(\.entry.spot).filter { picked.contains($0.id) })
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
                if !nearby.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button(picked.count == nearby.count ? "Select none" : "Select all") {
                            picked = picked.count == nearby.count ? [] : Set(nearby.map(\.entry.spot.id))
                        }
                    }
                }
            }
        }
    }
}

/// The screens you can go to from the list.
enum Route: Hashable {
    case detail(Spot)
    case edit(Spot)
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
            let hours = Units.hours(first.start, first.end, zone: zone)
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
