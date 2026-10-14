import SwiftUI
import MapKit
import CoreLocation

/// Add a spot: pick a spot on the map or in the list (popular spots built into the app, and spots other people
/// shared), or search for a place or tap the map, give it a name and choose the sport. A new spot starts with
/// the standard rules for its sport (the directions can be picked right after) and is shared with others.
struct AddSpotView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Called with the new spot, so the list can open its settings.
    var onAdd: (Spot) -> Void = { _ in }

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pin: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var sport: Sport = .wing
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var timeZone: TimeZone?
    @State private var location = CLLocationManager()
    @FocusState private var searching: Bool
    /// The middle of the map, for the popular spots nearby (nil while the map shows a whole country or more).
    @State private var center: CLLocation?
    /// Spots other people shared near the map.
    @State private var shared: [SharedSpots.Shared] = []
    /// A spot picked on the map.
    @State private var selectedID: String?
    @State private var askToShare = false
    /// An existing spot (same sport, within 500 m) the new one might be.
    @State private var duplicate: Nearby?

    /// A spot that can be added from the map or the list: built in, or shared by someone.
    struct Nearby {
        let spot: Spot
        let detail: String   // "Varberg" (built in) or "Added by Christian"
        let meters: Double
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $position, selection: $selectedID) { pins }
                    .mapControls { MapUserLocationButton() }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        let region = context.region
                        center = region.span.latitudeDelta > 4 ? nil
                            : CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                    }
                    .onTapGesture { point in
                        // A tap on a marker selects it (the map handles that); anywhere else drops a new pin.
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            if selectedID == nil { choose(coordinate, suggestedName: nil) }
                        }
                    }
                    .onChange(of: selectedID) { if selectedID != nil { pin = nil } }
                    .task(id: center.map { "\(Int($0.coordinate.latitude * 2)),\(Int($0.coordinate.longitude * 2))" }) {
                        // Shared spots near the map, fetched again when it moves about 50 km
                        if let place = center ?? location.location { shared = await SharedSpots.near(place) }
                    }
                }
                .frame(maxHeight: .infinity)

                Form {
                    // Our own search field: the system one (.searchable) hides Cancel and Add while you type.
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search for a place", text: $query)
                            .focused($searching)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Clear")
                        }
                    }
                    if !results.isEmpty {
                        ForEach(results, id: \.self) { item in
                            Button {
                                if let coordinate = item.placemark.location?.coordinate {
                                    choose(coordinate, suggestedName: item.name)
                                    position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))
                                }
                                query = ""
                                searching = false
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "")
                                    Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } else if let selected {
                        Section {
                            NearbyRow(item: selected)
                            Button("Add this spot") { addPopular(selected.spot) }
                                .bold()
                        }
                    } else if pin == nil {
                        Text("Or tap the map where the spot is.")
                            .foregroundStyle(.secondary)
                        if !suggestions.isEmpty {
                            Section("Spots nearby") {
                                ForEach(suggestions, id: \.spot.id) { item in
                                    Button { addPopular(item.spot) } label: {
                                        HStack {
                                            NearbyRow(item: item)
                                            Spacer()
                                            Image(systemName: "plus.circle")
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                    } else {
                        TextField("Name of the spot", text: $name)
                        Picker("Sport", selection: $sport) {
                            Label("Wing", systemImage: Sport.wing.symbol).tag(Sport.wing)
                            Label("Surf", systemImage: Sport.surf.symbol).tag(Sport.surf)
                            Label("Powder", systemImage: Sport.powder.symbol).tag(Sport.powder)
                        }
                        .pickerStyle(.segmented)
                        if Settings.shared.shareNewSpots == true && Account.shared.signedIn {
                            Text("This spot will be shared with other Kookout users. Change it under Edit, or for new spots in Settings.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: !results.isEmpty ? 330 : selected != nil ? 230 : pin == nil ? (suggestions.isEmpty ? 150 : 400) : 260)
            }
            .task(id: query) { await search() }
            .navigationTitle("Add spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let twin = nearbyTwin() { duplicate = twin; return }
                        // The first spot they make: ask whether to share it (and their spots from now on).
                        // (and ask again if they chose to share but aren't signed in: sharing needs an account)
                        let choice = Settings.shared.shareNewSpots
                        if choice == nil || (choice == true && !Account.shared.signedIn) { askToShare = true } else { add() }
                    }
                        .disabled(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(duplicate.map { String(localized: "Did you mean \($0.spot.name)?") } ?? "",
                                isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                                titleVisibility: .visible, presenting: duplicate) { twin in
                Button("Use \(twin.spot.name)") { addPopular(twin.spot) }
                Button("Add a new spot") { duplicate = nil; addOwn() }
                Button("Cancel", role: .cancel) { duplicate = nil }
            } message: { twin in
                Text("There's already a \(twin.spot.sport.label) spot \(Measurement.distance(twin.meters)) away. Following it keeps riders and fixes in one place.")
            }
            .sheet(isPresented: $askToShare) {
                ShareQuestion { share in
                    Settings.shared.shareNewSpots = share
                    askToShare = false
                    add()
                }
                                .interactiveDismissDisabled()
            }
            .onAppear {
                location.requestWhenInUseAuthorization()
                // Start about 80 km across around the phone, so the spots nearby show as pins.
                if let here = location.location {
                    position = .region(MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 80_000, longitudinalMeters: 80_000))
                }
            }
        }
    }

    /// The user's own spots in grey; the ones they can add in the accent colour (tap to pick); the new pin in green.
    @MapContentBuilder private var pins: some MapContent {
        ForEach(store.spots) { spot in
            Marker(spot.name, systemImage: spot.sport.symbol, coordinate: spot.coordinate).tint(.gray)
        }
        ForEach(onMap, id: \.spot.id) { item in
            Marker(item.spot.name, systemImage: item.spot.sport.symbol, coordinate: item.spot.coordinate)
                .tint(Color.accentColor)
                .tag(item.spot.id)
        }
        if let pin { Marker(name.isEmpty ? String(localized: "New spot") : name, coordinate: pin).tint(.green) }
        UserAnnotation()
    }

    private func choose(_ coordinate: CLLocationCoordinate2D, suggestedName: String?) {
        pin = coordinate
        if let suggestedName, name.isEmpty { name = suggestedName }
        timeZone = nil
        // The place's time zone, so the spot shows local time (e.g. Hawaiian time for Waikiki).
        Task {
            let placemark = try? await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first
            timeZone = placemark?.timeZone
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300)) // wait until the user stops typing
        guard !Task.isCancelled else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        results = (try? await MKLocalSearch(request: request).start().mapItems.prefix(8).map { $0 }) ?? []
    }

    /// Built-in and shared spots within 200 km of the middle of the map (or the phone, when the map is zoomed
    /// far out) that the user doesn't have yet, nearest first.
    private var nearby: [Nearby] {
        guard let place = center ?? location.location else { return [] }
        let mine = Set(store.spots.map(\.id))
        let builtIn = Catalogue.nearest(to: place, excluding: mine)
            .map { Nearby(spot: $0.entry.spot, detail: $0.entry.area, meters: $0.meters) }
        let others = shared.filter { !mine.contains($0.id) }
            .map { Nearby(spot: $0.spot, detail: Self.addedBy($0.by), meters: $0.location.distance(from: place)) }
            .filter { $0.meters <= Catalogue.nearbyMeters }
        return (builtIn + others).sorted { $0.meters < $1.meters }
    }

    private var suggestions: [Nearby] { Array(nearby.prefix(5)) }
    private var onMap: [Nearby] { Array(nearby.prefix(80)) }
    private var selected: Nearby? { selectedID.flatMap { id in nearby.first { $0.spot.id == id } } }

    static func addedBy(_ name: String?) -> String {
        if let name, !name.isEmpty { return String(localized: "Added by \(name)") }
        return String(localized: "Added by a Kookout user")
    }

    private func addPopular(_ spot: Spot) {
        store.add(spot)
        Task { await store.refresh(spot) }
        dismiss()
        onAdd(spot)
    }

    /// An existing spot for the same sport within 500 m of the new pin, nearest first.
    private func nearbyTwin() -> Nearby? {
        guard let pin else { return nil }
        let here = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
        let mine = Set(store.spots.map(\.id))
        let builtIn = Catalogue.nearest(to: here, excluding: mine).map { Nearby(spot: $0.entry.spot, detail: $0.entry.area, meters: $0.meters) }
        let others = shared.filter { !mine.contains($0.id) }
            .map { Nearby(spot: $0.spot, detail: Self.addedBy($0.by), meters: $0.location.distance(from: here)) }
        return (builtIn + others).filter { $0.meters <= 500 && $0.spot.sport == sport }.min { $0.meters < $1.meters }
    }

    /// After the duplicate check: the sharing question the first time, then add.
    private func addOwn() {
        let choice = Settings.shared.shareNewSpots
        if choice == nil || (choice == true && !Account.shared.signedIn) { askToShare = true } else { add() }
    }

    private func add() {
        guard let pin else { return }
        let rounded = { (v: Double) in (v * 10_000).rounded() / 10_000 }
        var spot = Spot(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                        latitude: rounded(pin.latitude), longitude: rounded(pin.longitude),
                        timeZoneID: (timeZone ?? .current).identifier)
        // As they answered (changeable under Edit); never public without an account
        spot.shared = Settings.shared.shareNewSpots == true && Account.shared.signedIn
        switch sport {
        case .wing: spot.wind = WindRule()
        case .surf: spot.surf = SurfRule()
        case .powder: spot.powder = PowderRule()
        }
        store.add(spot)
        Task { await store.refresh(spot) }
        dismiss()
        onAdd(spot)
    }
}

extension Spot {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// "Saltstein", with "Nevlunghavn · 90 km" or "Added by Christian · 12 km" under it.
struct NearbyRow: View {
    let item: AddSpotView.Nearby

    var body: some View {
        HStack {
            Image(systemName: item.spot.sport.symbol).frame(width: 24)
            VStack(alignment: .leading) {
                Text(item.spot.name)
                Text("\(item.detail) · \(Measurement.distance(item.meters))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Asked once, the first time someone makes a spot: share it (and later ones) with other Kookout users? Sharing
/// needs Sign in with Apple, and the name to show.
struct ShareQuestion: View {
    let answer: (Bool) -> Void
    private let account = Account.shared
    @State private var share = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share your spots with other Kookout users?").font(.headline)
                    Text("Others can then find them on the map, with their name, place and rules. Spots you keep private stay on your phone, and you can change this for each spot under Edit.")
                        .foregroundStyle(.secondary)
                    Picker("Share", selection: $share) {
                        Text("Share").tag(true)
                        Text("Keep private").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if share {
                    Section {
                        AccountRows()
                    } footer: {
                        Text(account.signedIn ? "Shown as “Added by …” on the spots you share, and next to changes you make."
                                              : "Sharing needs Sign in with Apple, so changes to spots show who made them. Kookout gets your name, not your email.")
                    }
                }
                Section {
                    Button(share ? "Share and add the spot" : "Add the spot") { answer(share) }
                        .bold()
                        .disabled(share && !account.signedIn)
                }
            }
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
