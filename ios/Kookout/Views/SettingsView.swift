import SwiftUI

/// Units, and starting over with the default spots.
struct SettingsView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var confirmReset = false

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
                    Button("Reset to the default spots", role: .destructive) { confirmReset = true }
                }

                Section {
                    Link("Privacy and support", destination: URL(string: "https://kookout.no/personvern.html")!)
                    Link("hi@kookout.no", destination: URL(string: "mailto:hi@kookout.no")!)
                } footer: {
                    Text("Forecasts from MET Norway (yr.no), Kystverket, NOAA and Holfuy.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Replace your spots with the default spots?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.resetToDefaults() }
            }
            // The rules round in the chosen units, so work everything out again when they change.
            .onChange(of: settings.wind) { Task { await store.refreshAll() } }
            .onChange(of: settings.wave) { Task { await store.refreshAll() } }
        }
    }
}
