import SwiftUI
import SwiftData

/// Profile tab — identity card, subscription state, settings sections,
/// Sign Out, Delete Account (Q15). The full settings sub-screens land in a
/// later round; this first cut wires identity + Sign Out so we can exercise
/// the auth round-trip end-to-end.
struct ProfileView: View {
    @Environment(AuthenticationManager.self) private var auth
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                identitySection

                Section("Subscription") {
                    HStack {
                        Label("Free", systemImage: "star.circle")
                        Spacer()
                        Text("Trial available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Settings") {
                    placeholderRow("Preferences", systemImage: "gear")
                    placeholderRow("Plan & Grocery defaults", systemImage: "calendar.badge.checkmark")
                    placeholderRow("Notifications", systemImage: "bell.badge")
                    placeholderRow("Appearance", systemImage: "paintbrush")
                    placeholderRow("Privacy", systemImage: "hand.raised")
                }

                Section("Help & About") {
                    placeholderRow("Help & Support", systemImage: "questionmark.circle")
                    placeholderRow("About", systemImage: "info.circle")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog(
                "Sign out of MealKit?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your recipes stay safe. Sign back in any time to restore.")
            }
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        if case .authenticated(let user) = auth.state {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName?.isEmpty == false ? user.displayName! : "Signed in")
                            .font(.headline)

                        if let email = user.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text("Member since \(user.createdAt, format: .dateTime.month(.abbreviated).year())")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.tint.opacity(0.6))
                        .accessibilityLabel("iCloud sync")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func placeholderRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
