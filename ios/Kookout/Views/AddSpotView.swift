import SwiftUI
import MapKit
import CoreLocation

/// Add a spot: pick one of the popular spots nearby, search for a place or tap the map, give it a name,
/// choose the sport. It starts with the standard rules for that sport; the directions can be picked right after.
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $position) {
                        if let pin { Marker(name.isEmpty ? String(localized: "New spot") : name, coordinate: pin) }
                        UserAnnotation()
                    }
                    .mapControls { MapUserLocationButton() }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        let region = context.region
                        center = region.span.latitudeDelta > 4 ? nil
                            : CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                    }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) { choose(coordinate, suggestedName: nil) }
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
                    } else if pin == nil {
                        Text("Or tap the map where the spot is.")
                            .foregroundStyle(.secondary)
                        if !suggestions.isEmpty {
                            Section("Popular spots nearby") {
                                ForEach(suggestions, id: \.entry.spot.id) { item in
                                    Button { addPopular(item.entry.spot) } label: {
                                        HStack {
                                            Image(systemName: item.entry.spot.sport.symbol).frame(width: 24)
                                            VStack(alignment: .leading) {
                                                Text(item.entry.spot.name)
                                                Text("\(item.entry.area) · \(Measurement.distance(item.meters))")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
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
                    }
                }
                .frame(height: !results.isEmpty ? 330 : pin == nil ? (suggestions.isEmpty ? 150 : 400) : 210)
            }
            .task(id: query) { await search() }
            .navigationTitle("Add spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(pin == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { location.requestWhenInUseAuthorization() }
        }
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

    /// The catalogue spots nearest the middle of the map (or the phone, when the map is zoomed far out),
    /// that the user doesn't have yet.
    private var suggestions: [(entry: Catalogue.Entry, meters: Double)] {
        guard let place = center ?? location.location else { return [] }
        return Catalogue.nearest(to: place, excluding: Set(store.spots.map(\.id)), count: 5)
    }

    private func addPopular(_ spot: Spot) {
        store.add(spot)
        Task { await store.refresh(spot) }
        dismiss()
        onAdd(spot)
    }

    private func add() {
        guard let pin else { return }
        let rounded = { (v: Double) in (v * 10_000).rounded() / 10_000 }
        var spot = Spot(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                        latitude: rounded(pin.latitude), longitude: rounded(pin.longitude),
                        timeZoneID: (timeZone ?? .current).identifier)
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
