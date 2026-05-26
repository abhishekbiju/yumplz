import SwiftUI
import SwiftData

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
