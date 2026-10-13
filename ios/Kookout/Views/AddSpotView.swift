import SwiftUI
import MapKit
import CoreLocation

/// Add a spot: search for a place or tap the map, give it a name, choose the sport.
/// It starts with the standard rules for that sport; the directions can be picked right after.
struct AddSpotView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var sport: Sport = .wing
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var timeZone: TimeZone?
    @State private var location = CLLocationManager()
    @FocusState private var searching: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $position) {
                        if let pin { Marker(name.isEmpty ? String(localized: "New spot") : name, coordinate: pin) }
                        UserAnnotation()
                    }
                    .mapControls { MapUserLocationButton() }
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
                .frame(height: !results.isEmpty ? 330 : pin == nil ? 150 : 210)
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
    }
}
