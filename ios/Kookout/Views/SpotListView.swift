import SwiftUI
import CoreLocation
import MapKit

struct SpotListView: View {
    @Environment(SpotStore.self) private var store
    @State private var showSettings = false
    /// The add-spot screen, when open; it carries where its map starts.
    @State private var adding: Adding?
    @State private var path: [Route] = []
    @State private var locating = false
    @State private var editMode: EditMode = .inactive
    /// Where to list the popular spots: the phone, or a place searched for (e.g. home, when away).
    @State private var pickNear: Place?
    @State private var searchPlace = false
    /// What to open once the picker has gone (one sheet at a time).
    @State private var afterPicker: AfterPicker?
    @State private var searched: Place?
    enum AfterPicker { case add(CLLocation?), search }
    /// Opening the add-spot screen, with the place its map starts at (nil: around the phone).
    struct Adding: Identifiable {
        let id = UUID()
        var startAt: CLLocation? = nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            listContent
        }
        .environment(\.backToList, BackToList { path = [] })
    }

    private var listContent: some View {
        @Bindable var store = store
        return Group {
            List {
                ForEach(store.spots) { spot in
                    NavigationLink(value: Route.detail(spot)) {
                        SpotRow(spot: spot, forecast: store.forecasts[spot.id], failed: store.failed.contains(spot.id))
                    }
                    // Long-press: rearrange the list (the same as Edit) or delete the spot
                    .contextMenu {
                        Button("Rearrange", systemImage: "arrow.up.arrow.down") {
                            withAnimation { editMode = .active }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.spots.removeAll { $0.id == spot.id }
                        }
                    }
                }
                .onDelete { store.spots.remove(atOffsets: $0) }
                .onMove { store.spots.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, $editMode)
            .overlay {
                if store.spots.isEmpty { welcome }
            }
            .navigationTitle("Kookout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.spots.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(editMode == .active ? "Done" : "Edit") {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Image("Wordmark") // KOOKOUT with the O's looking out (brand/)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 17)
                        .accessibilityLabel("Kookout")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { adding = Adding() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add spot")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $pickNear, onDismiss: {
                switch afterPicker {
                case .add(let start): adding = Adding(startAt: start)
                case .search: searchPlace = true
                case nil: break
                }
                afterPicker = nil
            }) { place in
                NearbyPicker(location: place.location, placeName: place.name,
                             addOwn: { afterPicker = .add(place.name == nil ? nil : place.location) },
                             searchElsewhere: { afterPicker = .search })
            }
            .sheet(isPresented: $searchPlace, onDismiss: {
                if let searched { pickNear = searched }
                searched = nil
            }) {
                PlaceSearchView { searched = Place(location: $0, name: $1) }
            }
            // A new spot opens straight in its settings (directions and limits); Back goes to its forecast.
            .sheet(item: $adding) { adding in
                AddSpotView(onAdd: { spot in path = [.detail(spot), .edit(spot)] }, startAt: adding.startAt)
            }
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
                Task { await store.refresh(spot) } // the notification is about the latest forecast: show that
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
                    if let here = await Locator.current() { pickNear = Place(location: here, name: nil) } else { adding = Adding() }
                    locating = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(locating)
            Button("Spots near another place") { searchPlace = true }
            Button("Add a spot on the map") { adding = Adding() }
        }
    }
}

/// A place to list the popular spots around, with its name when it was searched for (nil: where the phone is).
struct Place: Identifiable {
    let location: CLLocation
    let name: String?
    var id: String { "\(location.coordinate.latitude),\(location.coordinate.longitude)" }
}

/// The popular spots within 200 km, to pick from (for the welcome screen).
struct NearbyPicker: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let location: CLLocation
    /// The searched place, or nil for where the phone is.
    var placeName: String?
    /// "Add a spot on the map", for when there's nothing nearby.
    var addOwn: () -> Void
    /// "Spots near another place": e.g. home, for someone setting up while away.
    var searchElsewhere: () -> Void
    @State private var picked: Set<String> = []

    private var nearby: [(entry: Catalogue.Entry, meters: Double)] {
        Catalogue.nearest(to: location, excluding: Set(store.spots.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
              ForEach(nearby, id: \.entry.spot.id) { item in
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
              if !nearby.isEmpty {
                  Section {
                      Button("Spots near another place") { searchElsewhere(); dismiss() }
                  } footer: {
                      Text("Away from home? Look for the spots where you usually ride.")
                  }
              }
            }
            .overlay {
                if nearby.isEmpty {
                    ContentUnavailableView {
                        Label("No spots here yet", systemImage: "mappin.slash")
                    } description: {
                        Text("Be the first: add your own spot on the map. Or look near another place, like home.")
                    } actions: {
                        Button("Add a spot on the map") { addOwn(); dismiss() }
                            .buttonStyle(.borderedProminent)
                        Button("Spots near another place") { searchElsewhere(); dismiss() }
                    }
                }
            }
            .navigationTitle(placeName.map { String(localized: "Spots near \($0)") } ?? String(localized: "Spots near you"))
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

/// Search for a town or area, to pick from the popular spots there instead of near the phone.
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var picked: (CLLocation, String) -> Void
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Town or area", text: $query)
                        .focused($focused)
                        .autocorrectionDisabled()
                } footer: {
                    Text("For example where you live, to see the popular spots there.")
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        guard let location = item.placemark.location else { return }
                        picked(location, item.name ?? query)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "")
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .task(id: query) { await search() }
            .onAppear { focused = true }
            .navigationTitle("Spots near another place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300)) // wait until the user stops typing
        guard !Task.isCancelled else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        results = (try? await MKLocalSearch(request: request).start().mapItems.prefix(8).map { $0 }) ?? []
    }
}

/// Goes back to the list from any screen (e.g. after deleting a spot, whose forecast screen is gone too).
struct BackToList: Sendable {
    let action: @MainActor @Sendable () -> Void
    @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var backToList = BackToList {}
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
        if let first = forecast.upcomingGood.first {
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
    /// "wing", "surf" or "powder", in the phone's language, for sentences like "a surf spot".
    var label: String {
        switch self {
        case .wing: String(localized: "wing")
        case .surf: String(localized: "surf")
        case .powder: String(localized: "powder")
        }
    }

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
