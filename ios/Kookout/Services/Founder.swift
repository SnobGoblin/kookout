import Foundation
import StoreKit

/// Founding users: the first 2,000 people to use the App Store version use Kookout for free (relay/src/founders.js).
/// Once, the app asks Apple when this Apple ID first downloaded Kookout and tells the relay, which answers with the
/// number in line. TestFlight and Xcode builds have no real download, so they never get a number.
@MainActor @Observable
final class Founder {
    static let shared = Founder()

    /// The founding-user number, once known (kept, so it's asked only once).
    private(set) var number: Int? = UserDefaults.standard.object(forKey: "founderNumber") as? Int
    private(set) var founding: Bool = UserDefaults.standard.bool(forKey: "founding")

    /// "Founding user #312 · Kookout is free for you.", for a founding user; nil otherwise.
    var line: String? {
        guard let number, founding else { return nil }
        return String(localized: "Founding user #\(number) · Kookout is free for you.")
    }

    /// At launch: get the number if we don't have it yet. Quietly does nothing when offline; tries again next launch.
    func check() async {
        guard number == nil,
              case .verified(let app)? = try? await AppTransaction.shared,
              app.environment == .production else { return }
        var body: [String: Any] = ["key": SharedSpots.key,
                                   "first": app.originalPurchaseDate.formatted(.iso8601)]
        if #available(iOS 18.4, *) { body["transaction"] = app.appTransactionID } // the same after a reinstall
        var request = URLRequest(url: KookoutAPI.relay.appending(path: "founders"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = answer["number"] as? Int else { return }
        self.number = number
        founding = answer["founding"] as? Bool ?? false
        UserDefaults.standard.set(number, forKey: "founderNumber")
        UserDefaults.standard.set(founding, forKey: "founding")
    }
}
