import Foundation
import AuthenticationServices
import Security

/// The person's Kookout account: Sign in with Apple, only needed to share and edit spots. The app keeps Kookout's
/// session token in the Keychain; the relay keeps Apple's user id and the public name (see relay/src/auth.js).
@MainActor @Observable
final class Account {
    static let shared = Account()

    struct User: Codable, Equatable {
        let id: String
        var name: String
    }

    private(set) var user: User? { didSet { save() } }
    var signedIn: Bool { user != nil && token != nil }
    /// What went wrong at the last sign-in, delete or rename, shown under the button.
    private(set) var problem: String?

    private var token: String? {
        get { Keychain.read("session") }
        set { if let newValue { Keychain.write("session", newValue) } else { Keychain.delete("session") } }
    }
    /// Apple's id for this person, to ask Apple whether they've since stopped using Sign in with Apple for Kookout.
    private var appleUserID: String? {
        get { UserDefaults.standard.string(forKey: "appleUserID") }
        set { UserDefaults.standard.set(newValue, forKey: "appleUserID") }
    }

    private init() {
        user = (UserDefaults.standard.data(forKey: "account")).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }

    /// The request for the Sign in with Apple button: the name only (no email address).
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// The Sign in with Apple button's answer: hand Apple's token to the relay and keep our session.
    func finish(_ result: Result<ASAuthorization, Error>) async {
        problem = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { problem = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identity = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
                problem = String(localized: "Apple didn't send what Kookout needs. Try again.")
                return
            }
            let body: [String: Any?] = ["identityToken": identity,
                                        "authorizationCode": credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                                        "givenName": credential.fullName?.givenName]
            guard let answer = await call("POST", "auth/apple", body: body.compactMapValues { $0 }),
                  let token = answer["token"] as? String, let user = Self.user(from: answer) else { return }
            self.token = token
            self.appleUserID = credential.user
            self.user = user
            SharedSpots.resync() // spots they chose to share go up now that they can
        }
    }

    /// The public name, shown on shared spots and in the edit log.
    func rename(_ name: String) async {
        guard signedIn, let answer = await call("PUT", "me", body: ["name": name]), let user = Self.user(from: answer) else { return }
        self.user = user
    }

    func signOut() {
        token = nil
        appleUserID = nil
        user = nil
    }

    /// Deletes the account on the relay (which also tells Apple to revoke the sign-in). Shared spots stay for
    /// the people who use them, without the name.
    func delete() async -> Bool {
        guard signedIn, await call("DELETE", "me") != nil else { return false }
        signOut()
        return true
    }

    /// At launch: if the person stopped using Sign in with Apple for Kookout (in the iPhone's Settings), sign out.
    func checkStillSignedIn() async {
        guard let appleUserID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID)
        if state == .revoked || state == .notFound { signOut() }
    }

    /// Adds the session to a request to the relay.
    func authorize(_ request: inout URLRequest) {
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    // MARK: -

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async -> [String: Any]? {
        var request = URLRequest(url: KookoutAPI.relay.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            problem = String(localized: "Couldn't reach Kookout. Check the internet connection.")
            return nil
        }
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && path == "me" { signOut() } // the session is gone on the relay
        guard status == 200 else {
            problem = (answer["error"] as? String) ?? "HTTP \(status)"
            return nil
        }
        return answer
    }

    private static func user(from answer: [String: Any]) -> User? {
        guard let u = answer["user"] as? [String: Any], let id = u["id"] as? String else { return nil }
        return User(id: id, name: u["name"] as? String ?? "")
    }

    private func save() {
        UserDefaults.standard.set(user.flatMap { try? JSONEncoder().encode($0) }, forKey: "account")
    }
}

/// A few lines of Keychain, for the session token.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sternell.kookout",
         kSecAttrAccount as String: key]
    }
    static func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ key: String, _ value: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
