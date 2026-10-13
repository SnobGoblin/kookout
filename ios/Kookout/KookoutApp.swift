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
                .task { await Notifications.shared.start(spots: store.spots) }
                .onChange(of: scenePhase) { if scenePhase == .active { Task { await Notifications.shared.refreshStatus() } } }
        }
    }
}
