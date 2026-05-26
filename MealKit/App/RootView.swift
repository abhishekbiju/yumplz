import SwiftUI
import SwiftData

// MARK: - Deep link notification

extension Notification.Name {
    /// Posted when the app is opened via a `mealkit://import?text=…` URL.
    /// The `object` is the percent-decoded text `String`.
    static let mealKitImportDeepLink = Notification.Name("com.abhishekbiju.mealkit.importDeepLink")
}

/// Authentication switchboard. Per ADR 0003, the app is gated by Sign in with
/// Apple — there is no anonymous mode. This view decides which surface to
/// show based on `AuthenticationManager.state`:
///
/// - `.loading` → splash with a spinner while we check credential state
/// - `.unauthenticated` → `SignInWithAppleView`
/// - `.authenticated` → `MainTabView` (the 5-tab app)
///
/// The `AuthenticationManager` is created here (rather than at App level)
/// because it needs a `ModelContext`, which is only available once the
/// SwiftData container is alive.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var auth: AuthenticationManager?

    var body: some View {
        Group {
            if let auth {
                switch auth.state {
                case .loading:
                    SplashView()
                case .unauthenticated:
                    SignInWithAppleView()
                        .environment(auth)
                case .authenticated:
                    MainTabView()
                        .environment(auth)
                }
            } else {
                SplashView()
            }
        }
        .task {
            // Bootstrap the auth manager exactly once. Subsequent
            // appearance-driven `.task` invocations are no-ops.
            if auth == nil {
                let manager = AuthenticationManager(modelContext: modelContext)
                auth = manager
                await manager.restoreSession()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    // MARK: - Deep link handling

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "mealkit", url.host == "import" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
              !text.isEmpty else { return }
        NotificationCenter.default.post(name: .mealKitImportDeepLink, object: text)
    }
}

/// Shown while we resolve auth state on launch. Matches the app icon style so
/// the launch screen → splash → app transition feels continuous.
private struct SplashView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.tint)
            ProgressView()
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    RootView()
}
