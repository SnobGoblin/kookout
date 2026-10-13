import Foundation
import UIKit
import UserNotifications

/// Notifications come from Kookout's relay through Apple's push service: the app sends the relay the spots
/// that have notifications on (with their rules) and the settings; the relay checks them every hour and
/// pushes when good conditions come up within the chosen time, or change. No account is needed: the phone
/// is known only by a random id made here and Apple's push token.
@MainActor @Observable
final class Notifications {
    static let shared = Notifications()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var token: String?
    /// The spot to open, when a notification is tapped.
    var openSpotID: String?

    private var spots: [Spot] = []
    private var pendingSync: Task<Void, Never>?
    private let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }()

    /// At launch: ask for permission the first time, and get a push token if allowed.
    func start(spots: [Spot]) async {
        self.spots = spots
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshStatus()
    }

    /// The permission may have been changed in the iPhone's Settings while Kookout was in the background.
    func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications() // the token comes back to the app delegate
        } else if status == .denied {
            syncSoon()
        }
    }

    func didRegister(token data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        syncSoon()
    }

    /// The spots changed (added, edited, notifications switched on or off).
    func update(spots: [Spot]) {
        self.spots = spots
        syncSoon()
    }

    /// Settings changed (units, clock, how far ahead): tell the relay, after a moment's calm.
    func syncSoon() {
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    /// Sends a test notification through the relay, to check that everything works.
    func sendTest() async -> Bool {
        await sync()
        var request = URLRequest(url: devicesURL.appending(path: "test"))
        request.httpMethod = "POST"
        let response = try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse
        return response?.statusCode == 200
    }

    private var devicesURL: URL { KookoutAPI.relay.appending(path: "devices").appending(path: deviceID) }

    private func sync() async {
        var request = URLRequest(url: devicesURL)
        let wanted = spots.filter(\.notifies)
        if let token, status != .denied, !wanted.isEmpty {
            let settings = Settings.shared
            let body = Device(token: token, sandbox: Self.sandbox,
                              lang: Bundle.main.preferredLocalizations.first ?? "en",
                              units: settings.wind.rawValue, waveUnit: settings.wave.rawValue,
                              h12: settings.uses12Hour, tz: TimeZone.current.identifier,
                              windowHours: settings.notifyHours, spots: wanted.map(Device.Spot.init))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        } else {
            request.httpMethod = "DELETE" // nothing to notify about
        }
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Builds from Xcode get their pushes from Apple's sandbox; TestFlight and App Store builds don't.
    private static var sandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private struct Device: Encodable {
        let token: String, sandbox: Bool, lang: String, units: String, waveUnit: String, h12: Bool, tz: String
        let windowHours: Int
        let spots: [Spot]

        struct Spot: Encodable {
            let id: String, name: String, lat: Double, lon: Double, alt: Double?, tz: String
            let wind: WindRule?, surf: SurfRule?, powder: PowderRule?
            init(_ s: Kookout.Spot) {
                id = s.id; name = s.name; lat = s.latitude; lon = s.longitude; alt = s.altitude; tz = s.timeZoneID
                wind = s.wind; surf = s.surf; powder = s.powder
            }
        }
    }
}

/// Receives the push token from iOS, shows notifications while the app is open, and opens the spot when one
/// is tapped.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Notifications.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Couldn't register for notifications: \(error)")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let spotID = response.notification.request.content.userInfo["spot"] as? String
        await MainActor.run { Notifications.shared.openSpotID = spotID }
    }
}
