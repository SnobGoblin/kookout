import SwiftUI
import AuthenticationServices

/// Signing in (for sharing and editing spots), or, once signed in, the public name. Used in Settings and in the
/// question about sharing.
struct AccountRows: View {
    @Environment(\.colorScheme) private var colorScheme
    private let account = Account.shared
    @State private var name = ""

    var body: some View {
        if account.signedIn {
            TextField("Your name", text: $name)
                .textContentType(.givenName) // the keyboard suggests the name on the phone's own contact card
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await account.rename(name) } }
                .onAppear { name = account.user?.name ?? "" }
                .onDisappear { if name != account.user?.name { Task { await account.rename(name) } } }
        } else {
            SignInWithAppleButton(.signIn) { account.configure($0) } onCompletion: { result in
                Task { await account.finish(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        if let problem = account.problem {
            Text(problem).font(.footnote).foregroundStyle(.red)
        }
    }
}
