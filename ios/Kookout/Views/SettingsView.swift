import SwiftUI

/// Units, and starting over with the default spots.
struct SettingsView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var confirmReset = false
    @State private var testState = TestState.ready
    @State private var testProblem: String?
    private let notifications = Notifications.shared

    private enum TestState {
        case ready, sending, sent, failed
        var label: LocalizedStringKey {
            switch self {
            case .ready, .sending: "Send a test notification"
            case .sent: "Test sent"
            case .failed: "Couldn't send the test"
            }
        }
    }

    // What "Automatic" means on this phone, shown next to it.
    private var automaticWind: String { Settings.automaticWind == .ms ? "m/s" : String(localized: "knots") }
    private var automaticWave: String { Settings.automaticWave == .ft ? String(localized: "feet") : String(localized: "metres") }
    private var automaticTemp: String { Settings.automaticTemp == .f ? "°F" : "°C" }
    private var automaticClock: String { Settings.automaticClock == .h12 ? String(localized: "12-hour") : String(localized: "24-hour") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Wind", selection: $settings.windUnit) {
                        Text("Automatic (\(automaticWind))").tag(Settings.WindUnit.automatic)
                        Text("m/s").tag(Settings.WindUnit.ms)
                        Text("knots").tag(Settings.WindUnit.kn)
                    }
                    Picker("Waves", selection: $settings.waveUnit) {
                        Text("Automatic (\(automaticWave))").tag(Settings.WaveUnit.automatic)
                        Text("metres").tag(Settings.WaveUnit.m)
                        Text("feet").tag(Settings.WaveUnit.ft)
                    }
                    Picker("Temperature", selection: $settings.tempUnit) {
                        Text("Automatic (\(automaticTemp))").tag(Settings.TempUnit.automatic)
                        Text("°C").tag(Settings.TempUnit.c)
                        Text("°F").tag(Settings.TempUnit.f)
                    }
                    Picker("Clock", selection: $settings.clock) {
                        Text("Automatic (\(automaticClock))").tag(Settings.Clock.automatic)
                        Text("12-hour").tag(Settings.Clock.h12)
                        Text("24-hour").tag(Settings.Clock.h24)
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Good hours are judged on the numbers as shown, so changing units can shift a borderline hour.")
                }

                Section {
                    if notifications.status == .denied {
                        Text("Notifications are turned off for Kookout in the iPhone's Settings.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } else {
                        Picker("Look ahead", selection: $settings.notifyHours) {
                            ForEach(Settings.notifyChoices, id: \.self) { Text(Settings.hoursText($0)).tag($0) }
                        }
                        Button(testState.label) {
                            Task {
                                testState = .sending
                                testProblem = await notifications.sendTest()
                                testState = testProblem == nil ? .sent : .failed
                            }
                        }
                        .disabled(testState == .sending)
                        if let testProblem {
                            Text(testProblem).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Kookout tells you when good conditions come up within this time, and when they change. Nothing is sent between 22 and 07. Switch notifications on or off for each spot under Edit.")
                }

                Section {
                    Toggle("Share new spots", isOn: Binding(get: { settings.shareNewSpots == true },
                                                            set: { settings.shareNewSpots = $0 }))
                    if settings.shareNewSpots == true {
                        TextField("Your name (optional)", text: $settings.sharingName)
                            .textContentType(.givenName) // the keyboard suggests the name on the phone's own contact card
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Spots you make are shared with other Kookout users, so they can find them on the map. Your name is shown as “Added by …”; leave it empty to share without one. Each spot can be changed under Edit.")
                }

                Section {
                    Button("Start over", role: .destructive) { confirmReset = true }
                }

                Section {
                    Link("Privacy and support", destination: URL(string: "https://kookout.no/privacy.html")!)
                    Link("hi@kookout.no", destination: URL(string: "mailto:hi@kookout.no")!)
                } footer: {
                    Text("Forecasts from MET Norway (yr.no), Kystverket, NOAA and Holfuy.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove all your spots and settings, and start over?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.removeAll(); settings.reset(); dismiss() }
            }
            // The rules round in the chosen units, so work everything out again when they change.
            .onChange(of: settings.wind) { Task { await store.refreshAll() } }
            .onChange(of: settings.wave) { Task { await store.refreshAll() } }
        }
    }
}
