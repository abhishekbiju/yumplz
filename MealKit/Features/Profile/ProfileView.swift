import SwiftUI
import SwiftData

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
                    NavigationLink {
                        PreferencesView()
                    } label: {
                        Label("Preferences", systemImage: "gear")
                    }
                    NavigationLink {
                        PlanGroceryDefaultsView()
                    } label: {
                        Label("Plan & Grocery defaults", systemImage: "calendar.badge.checkmark")
                    }
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }

                Section("Help & About") {
                    Label("Help & Support", systemImage: "questionmark.circle")
                    Label("About", systemImage: "info.circle")
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

}
