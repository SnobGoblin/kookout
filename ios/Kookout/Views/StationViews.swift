import SwiftUI
import WebKit

/// Pick the station for a spot's "Measured now": automatic (the nearest with a recent reading) or any within 50 km.
struct StationPicker: View {
    @Binding var spot: Spot
    @State private var stations: [LiveWind.Station]?

    var body: some View {
        List {
            Button { spot.station = nil; spot.stationName = nil } label: {
                row(String(localized: "Automatic"), detail: automaticDetail, chosen: spot.station == nil)
            }
            if let stations {
                ForEach(stations) { s in
                    Button { spot.station = s.id; spot.stationName = s.name } label: {
                        row(s.name, detail: detail(s), chosen: spot.station == s.id)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .overlay { if stations == nil { ProgressView() } }
        .overlay {
            if stations?.isEmpty == true {
                ContentUnavailableView("No stations nearby", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
        .navigationTitle("Wind station")
        .navigationBarTitleDisplayMode(.inline)
        .task { stations = await LiveWind.stations(near: spot) }
    }

    /// What "Automatic" means here: the riders' choice when there is one, otherwise the nearest station.
    private var automaticDetail: String {
        guard let id = spot.community?.station else { return String(localized: "The nearest station with a recent reading") }
        let name = spot.community?.stationName ?? id
        return String(localized: "Most riders' choice: \(name)")
    }

    private func row(_ title: String, detail: String, chosen: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if chosen { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
    }

    private func detail(_ s: LiveWind.Station) -> String {
        let distance = Measurement.distance(s.km * 1000)
        if s.isHolfuy { return String(localized: "Holfuy · \(distance)") }
        guard let r = s.reading else { return distance }
        let wind = r.gust.map { "\(Units.wind(r.wind)) (\(Units.wind($0))) \(Units.windUnit)" } ?? "\(Units.wind(r.wind)) \(Units.windUnit)"
        return "\(distance) · \(wind) · \(r.time.formatted(.relative(presentation: .named)))"
    }
}

/// Holfuy's own live widget for a station (Holfuy only shares its readings with station owners).
struct HolfuyWidget: View {
    /// The widget on its own, to put in a list row: shrunk to fit, not scrollable.
    struct Embedded: View {
        let number: String
        var body: some View {
            WebView(url: HolfuyWidget.url(number), scrolls: false)
        }
    }

    static func url(_ number: String) -> URL {
        URL(string: "https://widget.holfuy.com/?station=\(number)&su=\(Settings.shared.wind == .kn ? "knots" : "m/s")&t=C&lang=en&mode=detailed")!
    }

    @Environment(\.dismiss) private var dismiss
    let number: String
    let name: String

    var body: some View {
        NavigationStack {
            WebView(url: Self.url(number))
                .navigationTitle(name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    fileprivate struct WebView: UIViewRepresentable {
        let url: URL
        var scrolls = true
        func makeUIView(context: Context) -> WKWebView {
            // The widget is made for a wider screen: shrink it to the phone's width once it has loaded
            let fit = WKUserScript(source: """
                setTimeout(function () {
                  var w = document.documentElement.scrollWidth;
                  if (w > window.innerWidth) document.body.style.zoom = window.innerWidth / w;
                }, 300);
                """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            let config = WKWebViewConfiguration()
            config.userContentController.addUserScript(fit)
            let view = WKWebView(frame: .zero, configuration: config)
            view.scrollView.isScrollEnabled = scrolls
            view.isOpaque = false
            view.load(URLRequest(url: url))
            return view
        }
        func updateUIView(_ view: WKWebView, context: Context) {}
    }
}
