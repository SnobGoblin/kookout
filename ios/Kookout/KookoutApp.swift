import SwiftUI

@main
struct KookoutApp: App {
    @State private var store = SpotStore()

    var body: some Scene {
        WindowGroup {
            SpotListView()
                .environment(store)
        }
    }
}
