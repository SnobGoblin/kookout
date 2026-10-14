import SwiftUI
import MapKit

/// Report a community spot, or a change someone made to one. Goes to Kookout (relay/src/reports.js).
struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    var edit: Community.LogEntry? = nil
    @State private var reason = "wrong"
    @State private var note = ""
    @State private var sending = false
    @State private var problem: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        Text("Wrong place or name").tag("wrong")
                        Text("Private place").tag("private")
                        Text("Spam or offensive").tag("offensive")
                        Text("Something else").tag("other")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(edit == nil ? "What's wrong with \(spot.name)?" : "What's wrong with this change?")
                }
                Section {
                    TextField("Tell us more (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Kookout reads every report. Thanks for helping keep the spots right.")
                }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }.disabled(sending)
                }
            }
            .alert("Thanks, we'll take a look.", isPresented: $sent) { Button("OK") { dismiss() } }
        }
    }

    private func send() async {
        sending = true
        problem = await Community.report(spot, edit: edit, reason: reason, note: note)
        sending = false
        if problem == nil { sent = true }
    }
}

/// Move a spot deliberately: a full map with a fixed crosshair; drag the map under it and save.
struct MoveSpotView: View {
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    let save: (CLLocationCoordinate2D) -> Void
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D

    static let maxMeters = 2000.0 // further than this it's a different spot (the relay checks it too)

    init(spot: Spot, save: @escaping (CLLocationCoordinate2D) -> Void) {
        self.spot = spot
        self.save = save
        _center = State(initialValue: spot.coordinate)
        _position = State(initialValue: .region(MKCoordinateRegion(center: spot.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)))
    }

    private var meters: Double {
        CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    Marker(String(localized: "Now"), coordinate: spot.coordinate).tint(.gray)
                }
                .mapStyle(.hybrid)
                .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
                Image(systemName: "plus.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Text(meters > Self.maxMeters ? "That's more than 2 km away: add it as a new spot instead."
                                                 : "Drag the map so the cross is where the spot is.")
                    if meters >= 5 && meters <= Self.maxMeters {
                        Text("Moves it \(Measurement.distance(meters))").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            .navigationTitle("Move \(spot.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save position") {
                        save(CLLocationCoordinate2D(latitude: (center.latitude * 10_000).rounded() / 10_000,
                                                    longitude: (center.longitude * 10_000).rounded() / 10_000))
                        dismiss()
                    }
                    .disabled(meters < 5 || meters > Self.maxMeters)
                }
            }
        }
    }
}

/// On the forecast screen: who added the spot and the latest change, opening the history.
struct CommunityLine: View {
    let spot: Spot

    var body: some View {
        if let community = spot.community {
            NavigationLink { SpotHistoryView(spot: spot) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(community.catalogue ? String(localized: "Popular spot") : AddSpotView.addedBy(community.by))
                    if let last = community.lastEdit {
                        Text(lastChange(last)).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
    }

    private func lastChange(_ e: Community.Info.Edit) -> String {
        let who = e.by.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "a Kookout user")
        let when = e.at.formatted(.relative(presentation: .named))
        return e.field == "name" ? String(localized: "Renamed by \(who) \(when)") : String(localized: "Moved by \(who) \(when)")
    }
}
