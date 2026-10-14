import SwiftUI
import MapKit

/// Edit a spot: name, position, the directions that work (tap the compass), and the limits for its sport.
/// Changes are kept in a copy and saved with "Done". For community spots, name and position change for everyone
/// (signed in, logged); the rules are the person's own.
struct SpotEditView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var spot: Spot
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var problem: String?
    private let original: Spot

    init(spot: Spot) {
        _spot = State(initialValue: spot)
        original = spot
    }

    private var isCommunity: Bool { spot.community != nil }
    /// Name and position: anyone's own spot, or a community spot when signed in.
    private var canFix: Bool { !isCommunity || Account.shared.signedIn }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $spot.name)
                    .disabled(!canFix)
                SpotPositionPicker(spot: $spot, enabled: canFix)
            } header: {
                Text("Name and position")
            } footer: {
                if isCommunity {
                    Text(canFix ? "Changes to the name or position are for everyone who follows this spot, and show your name in its history."
                                : "To fix the name or position for everyone, sign in with Apple in Settings.")
                } else {
                    Text("Tap the map to move the spot.")
                }
            }

            if let community = spot.community { communitySection(community) }

            if spot.wind != nil { windSection }
            if spot.surf != nil { surfSection }
            if spot.powder != nil { powderSection }

            if spot.shared != nil {
                Section {
                    Toggle("Share with others", isOn: Binding(get: { spot.shared == true }, set: { spot.shared = $0 }))
                        .disabled(!Account.shared.signedIn && spot.shared != true)
                } footer: {
                    Text(Account.shared.signedIn
                         ? "Other Kookout users can find this spot on the map: its name, place and rules, and your name."
                         : spot.shared == true
                            ? "You're signed out, so this spot isn't updated for others. Switch it off to stop sharing it, or sign in with Apple in Settings."
                            : "To share spots, sign in with Apple in Settings.")
                }
            } else if let by = spot.addedBy {
                Section { Text(AddSpotView.addedBy(by)).foregroundStyle(.secondary) }
            }

            Section {
                Toggle("Notifications", isOn: Binding(get: { spot.notifies }, set: { spot.notify = $0 }))
            } footer: {
                Text("When good conditions come up in the next \(Settings.hoursText(Settings.shared.notifyHours)), or change. How far ahead is set in Settings.")
            }

            Section {
                Button("Delete spot", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(spot.name.isEmpty ? String(localized: "Spot") : spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Task { await save() } }
                    .disabled(saving || spot.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
        .confirmationDialog("Delete \(spot.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.spots.removeAll { $0.id == spot.id }
                dismiss()
            }
        }
    }

    private func save() async {
        spot.name = spot.name.trimmingCharacters(in: .whitespaces)
        let renamed = spot.name != original.name
        let moved = spot.latitude != original.latitude || spot.longitude != original.longitude
        if isCommunity && (renamed || moved) {
            // For everyone: the relay checks and logs it, then the app takes over the community's version
            saving = true
            problem = await Community.edit(spot, name: renamed ? spot.name : nil,
                                           latitude: moved ? spot.latitude : nil, longitude: moved ? spot.longitude : nil,
                                           store: store)
            saving = false
            if problem != nil { return }
        }
        store.update(spot)
        Task { await store.refresh(spot) }
        dismiss()
    }

    // MARK: - Community

    private func communitySection(_ community: Community.Info) -> some View {
        Section {
            if Community.Rules(spot) != community.rules {
                Button("Use the community's rules") {
                    spot.wind = community.rules.wind; spot.surf = community.rules.surf; spot.powder = community.rules.powder
                }
            }
            NavigationLink("History") { SpotHistoryView(spot: spot) }
        } header: {
            Text("Community")
        } footer: {
            Text(community.followers == 1 ? String(localized: "You're the only one following this spot so far.")
                                          : String(localized: "Followed by \(community.followers) riders. The community's rules are the majority's; yours are your own."))
        }
    }

    // MARK: - Wing

    private var windSection: some View {
        Group {
            Section {
                CompassPicker(selected: dirsBinding(\.wind))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text("Directions that work")
            } footer: {
                Text("Tap to choose. The wind comes from these directions.")
            }
            Section("Good wind (\(Units.windUnit))") {
                WindStepper(title: "Mean wind at least", value: windBinding(\.min))
                WindStepper(title: "… with gusts at least", value: windBinding(\.gust))
                WindStepper(title: "… or steady wind at least", value: windBinding(\.steady))
                Stepper("Hours in a row: \(spot.wind!.hours)", value: windIntBinding(\.hours), in: 1...6)
                Toggle("Daylight only", isOn: windBoolBinding(\.daylight))
                Toggle("Own limit on sunny days", isOn: sunnyBinding)
                if spot.wind?.sunny != nil {
                    WindStepper(title: "Sunny days: mean wind at least", value: sunnyLimit(\.min))
                    WindStepper(title: "… with gusts at least", value: sunnyLimit(\.gust))
                    WindStepper(title: "… or steady wind at least", value: sunnyLimit(\.steady))
                }
            }
        }
    }

    private func windBinding(_ key: WritableKeyPath<WindRule, Double>) -> Binding<Double> {
        Binding(get: { spot.wind![keyPath: key] }, set: { spot.wind![keyPath: key] = $0 })
    }
    private func windIntBinding(_ key: WritableKeyPath<WindRule, Int>) -> Binding<Int> {
        Binding(get: { spot.wind![keyPath: key] }, set: { spot.wind![keyPath: key] = $0 })
    }
    private func windBoolBinding(_ key: WritableKeyPath<WindRule, Bool>) -> Binding<Bool> {
        Binding(get: { spot.wind![keyPath: key] }, set: { spot.wind![keyPath: key] = $0 })
    }
    /// Turning on the sunny-day limit starts one step below the normal limits (like Drøbak's 4 (8) / 5+).
    private var sunnyBinding: Binding<Bool> {
        Binding(get: { spot.wind?.sunny != nil }, set: { on in
            guard let r = spot.wind else { return }
            spot.wind!.sunny = on ? .init(min: max(0, r.min - 1), gust: max(0, r.gust - 1), steady: max(0, r.steady - 1)) : nil
        })
    }
    private func sunnyLimit(_ key: WritableKeyPath<WindRule.Limits, Double>) -> Binding<Double> {
        Binding(get: { spot.wind?.sunny?[keyPath: key] ?? 0 }, set: { spot.wind!.sunny![keyPath: key] = $0 })
    }

    // MARK: - Surf

    private var surfSection: some View {
        Group {
            Section {
                CompassPicker(selected: dirsBinding(\.surf))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text("Wind directions that work")
            } footer: {
                Text("For example offshore wind. Tap to choose.")
            }
            Section("Good surf") {
                HStack {
                    Text("Waves at least")
                    Spacer()
                    StepButtons(label: "\(Units.wave(spot.surf!.minWave)) \(Units.waveUnit)",
                                down: { spot.surf!.minWave = Units.stepWave(spot.surf!.minWave, by: -1) },
                                up: { spot.surf!.minWave = Units.stepWave(spot.surf!.minWave, by: 1) })
                }
                HStack {
                    Text("Period at least")
                    Spacer()
                    StepButtons(label: spot.surf!.minPeriod > 0 ? "\(Int(spot.surf!.minPeriod)) s" : String(localized: "off"),
                                down: { spot.surf!.minPeriod = max(0, spot.surf!.minPeriod - 1) },
                                up: { spot.surf!.minPeriod += 1 })
                }
                WindStepper(title: "Wind at most",
                            value: Binding(get: { spot.surf!.maxWind }, set: { spot.surf!.maxWind = $0 }))
                Stepper("Hours in a row: \(spot.surf!.hours)",
                        value: Binding(get: { spot.surf!.hours }, set: { spot.surf!.hours = $0 }), in: 1...6)
                Toggle("Daylight only", isOn: Binding(get: { spot.surf!.daylight }, set: { spot.surf!.daylight = $0 }))
            }
        }
    }

    // MARK: - Powder

    private var powderSection: some View {
        Section("Powder") {
            Stepper("Precipitation in a day over \(Int(spot.powder!.mm)) mm",
                    value: Binding(get: { spot.powder!.mm }, set: { spot.powder!.mm = $0 }), in: 0...100)
            HStack {
                Text("Colder than")
                Spacer()
                StepButtons(label: "\(Units.temp(spot.powder!.maxTemp))\(Settings.shared.temp == .f ? "F" : "C")",
                            down: { spot.powder!.maxTemp = Units.stepTemp(spot.powder!.maxTemp, by: -1) },
                            up: { spot.powder!.maxTemp = Units.stepTemp(spot.powder!.maxTemp, by: 1) })
            }
            WindStepper(title: "Wind under",
                        value: Binding(get: { spot.powder!.maxWind }, set: { spot.powder!.maxWind = $0 }))
        }
    }

    // MARK: - Shared

    /// The directions of the spot's wind or surf rule.
    private func dirsBinding<R>(_ rule: WritableKeyPath<Spot, R?>) -> Binding<Set<String>> where R: HasDirections {
        Binding(get: { Set(spot[keyPath: rule]?.dirs ?? []) },
                set: { spot[keyPath: rule]?.dirs = Compass.points.filter($0.contains) })
    }
}

protocol HasDirections { var dirs: [String] { get set } }
extension WindRule: HasDirections {}
extension SurfRule: HasDirections {}

/// A wind speed with − / + buttons, stepping 1 m/s or 1 knot (stored in m/s).
struct WindStepper: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            StepButtons(label: Units.wind(value),
                        down: { value = Units.stepWind(value, by: -1) },
                        up: { value = Units.stepWind(value, by: 1) })
        }
    }
}

struct StepButtons: View {
    let label: String
    let down: () -> Void
    let up: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: down) { Image(systemName: "minus") }
            Text(label).monospacedDigit().frame(minWidth: 44)
            Button(action: up) { Image(systemName: "plus") }
        }
        .buttonStyle(.bordered)
        .labelsHidden()
    }
}

/// 16 wedges you tap to switch a direction on (green) or off, like the web page.
struct CompassPicker: View {
    @Binding var selected: Set<String>

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(Compass.points.enumerated()), id: \.offset) { i, name in
                    Wedge(index: i)
                        .fill(selected.contains(name) ? Color.green : Color.gray.opacity(0.25))
                        .overlay(Wedge(index: i).stroke(Color(.systemBackground), lineWidth: 1.5))
                        .contentShape(Wedge(index: i))
                        .onTapGesture { toggle(name) }
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(selected.contains(name) ? [.isButton, .isSelected] : .isButton)
                }
                ForEach(["N", "E", "S", "W"], id: \.self) { name in
                    let angle = Angle.degrees(Double(Compass.points.firstIndex(of: name)! * 360 / 16) - 90)
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                        .position(x: size / 2 + cos(angle.radians) * size * 0.47, y: size / 2 + sin(angle.radians) * size * 0.47)
                }
                Text("from").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 240)
    }

    private func toggle(_ name: String) {
        if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
    }

    private struct Wedge: Shape {
        let index: Int
        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer = min(rect.width, rect.height) * 0.4, inner = outer * 0.4
            let start = Angle.degrees(Double(index) * 22.5 - 90 - 11.25), end = Angle.degrees(Double(index) * 22.5 - 90 + 11.25)
            var p = Path()
            p.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
            p.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
            p.closeSubpath()
            return p
        }
    }
}

/// A small map of the spot; tap to move it.
struct SpotPositionPicker: View {
    @Binding var spot: Spot
    let enabled: Bool
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                Marker(spot.name, systemImage: spot.sport.symbol, coordinate: spot.coordinate)
            }
            .onTapGesture { point in
                guard enabled, let c = proxy.convert(point, from: .local) else { return }
                spot.latitude = (c.latitude * 10_000).rounded() / 10_000
                spot.longitude = (c.longitude * 10_000).rounded() / 10_000
            }
        }
        .frame(height: 200)
        .listRowInsets(EdgeInsets())
        .onAppear {
            position = .region(MKCoordinateRegion(center: spot.coordinate, latitudinalMeters: 2500, longitudinalMeters: 2500))
        }
    }
}
