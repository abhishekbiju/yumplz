import SwiftUI
import SwiftData
import AuthenticationServices

/// Onboarding entry point. Per ADR 0003, this is a hard gate — there is no
/// "Skip" option. Per Apple HIG, the Sign in with Apple button shape and
/// color is fixed (we choose `.black` on light, `.white` on dark).
struct SignInWithAppleView: View {
    @Environment(AuthenticationManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            WarmGlassBackground()

            VStack(spacing: 0) {
                Spacer()

                // App icon + wordmark
                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 120, height: 120)
                        Circle()
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                            .frame(width: 120, height: 120)
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Color.accentColor)
                    }
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 20, y: 8)

                    VStack(spacing: 8) {
                        Text("MealKit")
                            .font(.mkDisplay)

                        Text("Save any recipe. Cook it later.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                // Feature bullets
                VStack(alignment: .leading, spacing: 14) {
                    FeatureBullet(icon: "brain.filled.head.profile",
                                  text: "AI parsing runs entirely on your device — no cloud, no cost.")
                    FeatureBullet(icon: "icloud.fill",
                                  text: "Your recipes sync across all your iPhone and iPad devices.")
                    FeatureBullet(icon: "lock.fill",
                                  text: "Sign in with Apple keeps your identity private.")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .glassCard(cornerRadius: 24)
                .padding(.horizontal, 24)

                Spacer(minLength: 32)

                // Sign in button
                VStack(spacing: 14) {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            Task { await auth.handleSignIn(result: result) }
                        }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .padding(.horizontal, 32)
                    .accessibilityLabel("Sign in with Apple")

                    Text("Your data never leaves your device or Apple's servers.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

#if DEBUG
                    // ── Debug-only bypass ─────────────────────────────────
                    // Skips Sign in with Apple. Stripped from Release builds.
                    // Remove once you enroll in the Apple Developer Program.
                    Divider().padding(.horizontal, 40)

                    Button("Continue without signing in (Dev)") {
                        auth.signInAsDevUser()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
#endif
                }
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - Feature bullet

private struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}

// MARK: - Preview

#Preview {
    SignInWithAppleView()
        .environment(PreviewAuthenticationManager.shared)
}

@MainActor
private enum PreviewAuthenticationManager {
    static let shared: AuthenticationManager = {
        let schema = Schema([
            User.self, Recipe.self, Ingredient.self, Step.self,
            RecipeCollection.self, PlannedMeal.self, GroceryList.self, GroceryItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return AuthenticationManager(modelContext: container.mainContext)
    }()
}
