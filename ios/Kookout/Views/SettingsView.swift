import SwiftUI

/// Units, notifications, sharing, starting over, and about the app.
struct SettingsView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var confirmReset = false
    @State private var testState = TestState.ready
    @State private var testProblem: String?
    @State private var confirmDelete = false
    private let account = Account.shared
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

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

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
                        Picker("Weekend spots", selection: $settings.weekendNotifyHours) {
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
                    AccountRows()
                    if account.signedIn {
                        Toggle("Share new spots", isOn: Binding(get: { settings.shareNewSpots == true },
                                                                set: { settings.shareNewSpots = $0 }))
                    } else {
                        // Signed out, a tap anywhere on the row asks to sign in with Apple first (sharing needs an account)
                        Button {
                            Task { if await account.signIn() { settings.shareNewSpots = true } }
                        } label: {
                            HStack {
                                Text("Share new spots")
                                Spacer()
                                Toggle("Share new spots", isOn: .constant(false)).labelsHidden().allowsHitTesting(false)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if account.signedIn {
                        Button("Sign out") { account.signOut() }
                        Button("Delete account", role: .destructive) { confirmDelete = true }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text(account.signedIn
                         ? "Spots you make are shared with other Kookout users, so they can find them on the map. Your name is shown as “Added by …” and next to changes you make. Each spot can be changed under Edit."
                         : "Sign in with Apple to share spots and edit spots others share. Kookout gets your name, not your email. Everything else works without an account.")
                }

                Section {
                    Button("Start over", role: .destructive) { confirmReset = true }
                } footer: {
                    Text(account.signedIn ? "Removes all your spots and settings. You stay signed in."
                                          : "Removes all your spots and settings.")
                }

                Section {
                    Text("Kookout is made by Christian Sternell, a wing foiler in Norway who wanted to know when and where it's good, without checking the forecast again and again. Kookout knows what makes each of your spots work and tells you when it's on. Ideas, bugs or a spot that's judged wrong? Write to me, I read everything.")
                    Link("hi@kookout.no", destination: URL(string: "mailto:hi@kookout.no")!)
                    Link("Privacy and support", destination: URL(string: "https://kookout.no/privacy.html")!)
                } header: {
                    Text("About Kookout")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let line = Founder.shared.line { Text(line) }
                        Text("Forecasts from MET Norway (yr.no), Kystverket, NOAA and Holfuy.")
                        // The build number tells which TestFlight build a tester is on.
                        Text("Version \(Self.version) (\(Self.build))")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete your Kookout account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { _ = await account.delete() } }
            } message: {
                Text("Your spots stay on this phone. Spots you shared stay for the people who use them, without your name.")
            }
            // An alert, not a menu: it can't be undone, so it should stop the person and say what goes.
            .alert("Start over?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Remove everything", role: .destructive) {
                    store.removeAll(); settings.reset(); LiveWind.latest = [:]; dismiss()
                }
            } message: {
                // "You stay signed in" only when they are
                if account.signedIn {
                    Text("This removes all your spots (\(store.spots.count)) with your own rules and wind stations, and sets units, notifications and sharing back to how they were at the start. You stay signed in with Apple. This can't be undone.")
                } else {
                    Text("This removes all your spots (\(store.spots.count)) with your own rules and wind stations, and sets units, notifications and sharing back to how they were at the start. This can't be undone.")
                }
            }
            // The rules round in the chosen units, so work everything out again when they change.
            .onChange(of: settings.wind) { Task { await store.refreshAll() } }
            .onChange(of: settings.wave) { Task { await store.refreshAll() } }
        }
    }
}
