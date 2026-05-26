import Foundation
import AuthenticationServices
import SwiftData
import SwiftUI

/// Owns the active User identity for this device. Wraps Sign in with Apple,
/// persists the User to SwiftData on first sign-in, and tracks the per-device
/// "active session" pointer in UserDefaults.
///
/// Why both UserDefaults and SwiftData:
/// - The User entity is part of the synced data model (so the User row survives
///   across devices and reinstalls via CloudKit).
/// - The "active session" pointer is per-device (so signing out on iPhone
///   doesn't sign you out on iPad).
///
/// Per ADR 0003: Sign in with Apple is required, no anonymous mode.
/// Per Q15: Sign Out preserves user data; Delete Account is the destructive op.
@MainActor
@Observable
final class AuthenticationManager {

    enum AuthState {
        case loading
        case unauthenticated
        case authenticated(User)
    }

    private(set) var state: AuthState = .loading

    private let modelContext: ModelContext

    /// UserDefaults key for the per-device active Apple user ID.
    private static let activeUserIDKey = "com.abhishekbiju.mealkit.activeAppleUserID"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Debug bypass

#if DEBUG
    /// Skips Sign in with Apple entirely, using a local synthetic User.
    /// Only available in DEBUG builds — stripped from Release by the compiler.
    func signInAsDevUser() {
        let devID = "dev-bypass-user"
        if let existing = fetchUser(forAppleUserID: devID) {
            UserDefaults.standard.set(devID, forKey: Self.activeUserIDKey)
            state = .authenticated(existing)
            return
        }
        let user = User(appleUserID: devID, displayName: "Dev User", email: nil)
        modelContext.insert(user)
        try? modelContext.save()
        UserDefaults.standard.set(devID, forKey: Self.activeUserIDKey)
        state = .authenticated(user)
    }
#endif

    // MARK: -

    /// Called on app launch from `RootView`. Determines whether we land on the
    /// sign-in screen or the main tabs.
    func restoreSession() async {
        guard let activeUserID = UserDefaults.standard.string(forKey: Self.activeUserIDKey) else {
            state = .unauthenticated
            return
        }

#if DEBUG
        // Dev bypass user has no real Apple credential — skip the SIWA check.
        if activeUserID == "dev-bypass-user" {
            if let user = fetchUser(forAppleUserID: activeUserID) {
                state = .authenticated(user)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeUserIDKey)
                state = .unauthenticated
            }
            return
        }
#endif

        // Verify the Apple credential is still authorized. If the user revoked
        // access in Settings, or the credential was transferred, force re-auth.
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState: ASAuthorizationAppleIDProvider.CredentialState
        do {
            credentialState = try await provider.credentialState(forUserID: activeUserID)
        } catch {
            // Network/keychain hiccup. Bias toward "still authenticated" so a
            // bad-network launch doesn't kick the user out of their app. We'll
            // re-verify on next launch.
            if let user = fetchUser(forAppleUserID: activeUserID) {
                state = .authenticated(user)
            } else {
                state = .unauthenticated
            }
            return
        }

        switch credentialState {
        case .authorized:
            if let user = fetchUser(forAppleUserID: activeUserID) {
                state = .authenticated(user)
            } else {
                // Active session points to a User we don't have locally yet
                // (e.g., fresh install before CloudKit sync completes). Treat
                // as unauthenticated; next sign-in will hydrate.
                UserDefaults.standard.removeObject(forKey: Self.activeUserIDKey)
                state = .unauthenticated
            }
        case .revoked, .notFound, .transferred:
            UserDefaults.standard.removeObject(forKey: Self.activeUserIDKey)
            state = .unauthenticated
        @unknown default:
            state = .unauthenticated
        }
    }

    /// Called from `SignInWithAppleButton`'s `onCompletion`.
    func handleSignIn(result: Result<ASAuthorization, Error>) async {
        guard
            case .success(let authorization) = result,
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else {
            // User cancelled or auth failed. Stay on the sign-in screen; the
            // button is still available.
            return
        }

        let appleUserID = credential.user

        // If we already have a User for this Apple ID locally, re-use it.
        // Apple only provides name/email on the *first* sign-in; we keep the
        // values we captured originally rather than overwriting with nil.
        if let existing = fetchUser(forAppleUserID: appleUserID) {
            UserDefaults.standard.set(appleUserID, forKey: Self.activeUserIDKey)
            state = .authenticated(existing)
            return
        }

        // First sign-in: capture identity payload.
        let displayName: String? = {
            guard let components = credential.fullName else { return nil }
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: components)
            return name.isEmpty ? nil : name
        }()

        let user = User(
            appleUserID: appleUserID,
            displayName: displayName,
            email: credential.email
        )
        modelContext.insert(user)

        do {
            try modelContext.save()
        } catch {
            // Avoid crashing in DEBUG when SwiftData save fails intermittently
            // (e.g. transient store/schema issues while iterating). Keep the app
            // on the auth screen so the user can retry instead of hard-crashing.
            print("⚠️ Failed to persist new User: \(error)")
            UserDefaults.standard.removeObject(forKey: Self.activeUserIDKey)
            state = .unauthenticated
            return
        }

        UserDefaults.standard.set(appleUserID, forKey: Self.activeUserIDKey)
        state = .authenticated(user)
    }

    /// Sign Out — preserves all user data per Q15. Clears the per-device
    /// active session pointer; the User entity and all Recipes stay.
    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.activeUserIDKey)
        state = .unauthenticated
    }

    private func fetchUser(forAppleUserID id: String) -> User? {
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.appleUserID == id }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }
}
