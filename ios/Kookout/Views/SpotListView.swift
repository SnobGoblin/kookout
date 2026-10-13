import SwiftUI

struct SpotListView: View {
    @State private var spots = Spot.defaults

    var body: some View {
        NavigationStack {
            List(spots) { spot in
                NavigationLink(value: spot) {
                    Label(spot.name, systemImage: spot.sport.symbol)
                }
            }
            .navigationTitle("Kookout")
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
        }
    }
}

extension Sport {
    /// SF Symbols for the sports (placeholders until the app has its own icons).
    var symbol: String {
        switch self {
        case .wing: "wind"
        case .surf: "water.waves"
        case .powder: "snowflake"
        }
    }
}

#Preview {
    SpotListView()
}
