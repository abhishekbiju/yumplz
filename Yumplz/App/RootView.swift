import SwiftUI
import SwiftData

// MARK: - Deep link notification

extension Notification.Name {
    /// Posted when the app is opened via a `yumplz://import?text=…` URL.
    /// The `object` is the percent-decoded text `String`.
    static let yumplzImportDeepLink = Notification.Name("com.abhishekbiju.yumplz.importDeepLink")
    /// Posted when the Share Extension opens the app via `yumplz://import?launch=1`.
    static let yumplzPendingImportLaunch = Notification.Name("com.abhishekbiju.yumplz.pendingImportLaunch")
}

enum YumplzImportDeepLinkUserInfoKey {
    static let autoStart = "autoStart"
    static let extractionMode = "extractionMode"
    static let importKind = "importKind"
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
#if DEBUG
                if ProcessInfo.processInfo.environment["YUMPLZ_SCREENSHOT_MODE"] == "1",
                   case .unauthenticated = manager.state {
                    manager.signInAsDevUser()
                }
#endif
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        #if DEBUG
        .task {
            // DEBUG-only test seam: lets us drive the share-import deep link from
            // `simctl launch` (env var) without the system "Open in app?" consent
            // dialog. Never compiled into release builds.
            if let raw = ProcessInfo.processInfo.environment["YUMPLZ_TEST_DEEPLINK"],
               let url = URL(string: raw) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                handleDeepLink(url)
            }
        }
        #endif
    }

    // MARK: - Deep link handling

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "yumplz", url.host == "import" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // Share Extension launch — MainTabView drains queue on first appear.
        if components.queryItems?.contains(where: { $0.name == "launch" && $0.value == "1" }) == true {
            NotificationCenter.default.post(name: .yumplzPendingImportLaunch, object: nil)
            return
        }

        guard let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
              !text.isEmpty else { return }
        let autoStart = components.queryItems?.first(where: { $0.name == "autostart" })?.value != "0"
        let userInfo: [String: Any] = [YumplzImportDeepLinkUserInfoKey.autoStart: autoStart]
        ShareImportDelivery.storePendingDeepLink(payload: text, userInfo: userInfo)
        NotificationCenter.default.post(
            name: .yumplzImportDeepLink,
            object: text,
            userInfo: userInfo
        )
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
