import SwiftUI

/// Units, and starting over with the default spots.
struct SettingsView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Wind", selection: $settings.windUnit) {
                        Text("m/s").tag(Settings.WindUnit.ms)
                        Text("knots").tag(Settings.WindUnit.kn)
                    }
                    Picker("Waves", selection: $settings.waveUnit) {
                        Text("metres").tag(Settings.WaveUnit.m)
                        Text("feet").tag(Settings.WaveUnit.ft)
                    }
                    Picker("Temperature", selection: $settings.tempUnit) {
                        Text("°C").tag(Settings.TempUnit.c)
                        Text("°F").tag(Settings.TempUnit.f)
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
            .onChange(of: settings.windUnit) { Task { await store.refreshAll() } }
            .onChange(of: settings.waveUnit) { Task { await store.refreshAll() } }
        }
    }
}
