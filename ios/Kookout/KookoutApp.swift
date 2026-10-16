import SwiftUI

@main
struct KookoutApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = SpotStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var splash = true

    var body: some Scene {
        WindowGroup {
            SpotListView()
                .environment(store)
                .overlay {
                    if splash {
                        SplashView { withAnimation(.easeOut(duration: 0.3)) { splash = false } }
                            .transition(.opacity)
                    }
                }
                .task {
                    await Account.shared.checkStillSignedIn()
                    SharedSpots.sync(old: [], new: store.spots) // re-share at launch, in case a share failed (offline)
                    Community.syncSoon(store) // the community's latest names, positions and rules
                    await Notifications.shared.start(spots: store.spots)
                    await Founder.shared.check()
                }
                .onChange(of: scenePhase) {
                    guard scenePhase == .active else { return }
                    Task { await Notifications.shared.refreshStatus() }
                    Task { await store.refreshIfStale() } // forecasts from last night aren't today's
                }
        }
    }
}
