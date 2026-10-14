import SwiftUI
import CoreLocation

/// The log of a community spot: who added it, renamed it or moved it, and when. Anyone signed in can undo a change.
struct SpotHistoryView: View {
    @Environment(SpotStore.self) private var store
    let spot: Spot
    @State private var entries: [Community.LogEntry]?
    @State private var problem: String?

    var body: some View {
        List {
            if let entries {
                ForEach(entries) { entry in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(describe(entry))
                            Text(entry.at, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if entry.undone {
                            Text("Undone").font(.caption).foregroundStyle(.secondary)
                        } else if canUndo(entry) {
                            Button("Undo") { Task { await undo(entry) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        }
        .overlay { if entries == nil && problem == nil { ProgressView() } }
        .overlay {
            if entries?.isEmpty == true {
                ContentUnavailableView("No changes yet", systemImage: "clock",
                                       description: Text("Name and position changes show up here, with who made them."))
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if let fresh = await Community.history(spot) { entries = fresh; problem = nil }
        else { problem = String(localized: "Couldn't reach Kookout. Check the internet connection.") }
    }

    private func canUndo(_ e: Community.LogEntry) -> Bool {
        Account.shared.signedIn && (e.field == "name" || e.field == "position") && e.undoes == nil
    }

    private func undo(_ e: Community.LogEntry) async {
        problem = await Community.undo(e, store: store)
        await load()
    }

    private func describe(_ e: Community.LogEntry) -> String {
        let who = e.by.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "a Kookout user")
        switch e.field {
        case "created":
            return String(localized: "Added by \(who)")
        case "name":
            let from = e.old as? String ?? "", to = e.new as? String ?? ""
            return e.undoes == nil ? String(localized: "Renamed from “\(from)” to “\(to)” by \(who)")
                                   : String(localized: "Name changed back to “\(to)” by \(who)")
        case "position":
            let meters = distance(e.old, e.new)
            let how = Measurement.distance(meters)
            return e.undoes == nil ? String(localized: "Moved \(how) by \(who)")
                                   : String(localized: "Moved back \(how) by \(who)")
        default:
            return e.field
        }
    }

    private func distance(_ a: Any?, _ b: Any?) -> Double {
        guard let a = a as? [String: Any], let b = b as? [String: Any],
              let la = a["lat"] as? Double, let lo = a["lon"] as? Double,
              let lb = b["lat"] as? Double, let lob = b["lon"] as? Double else { return 0 }
        return CLLocation(latitude: la, longitude: lo).distance(from: CLLocation(latitude: lb, longitude: lob))
    }
}
