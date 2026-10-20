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
                // A spot tapped in the widget (kookout://spot/<id>) opens that spot, like a tapped notification.
                .onOpenURL { url in
                    if let id = WidgetData.spotID(from: url) { Notifications.shared.openSpotID = id }
                }
                .task {
                    WidgetBridge.update(spots: store.spots) // the widget's copy, in case the app was updated
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
