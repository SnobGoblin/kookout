import SwiftUI

@main
struct KookoutApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = SpotStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SpotListView()
                .environment(store)
                .task {
                    SharedSpots.sync(old: [], new: store.spots) // re-share at launch, in case a share failed (offline)
                    await Notifications.shared.start(spots: store.spots)
                }
                .onChange(of: scenePhase) {
                    guard scenePhase == .active else { return }
                    Task { await Notifications.shared.refreshStatus() }
                    Task { await store.refreshIfStale() } // forecasts from last night aren't today's
                }
        }
    }
}
