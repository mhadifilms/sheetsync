import SwiftUI

struct AccountManagementView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var showSignOutConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Account")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Content
            VStack(spacing: 24) {
                // Account info
                if appState.isAuthenticated {
                    VStack(spacing: 16) {
                        // Profile icon
                        ZStack {
                            Circle()
                                .fill(Color.blue.gradient)
                                .frame(width: 80, height: 80)

                            Text(initials)
                                .font(.title)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }

                        // Email
                        if let email = appState.userEmail {
                            Text(email)
                                .font(.headline)
                        }

                        // Status
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected to Google")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 24)

                    Spacer()

                    // Stats
                    VStack(spacing: 12) {
                        HStack {
                            StatBox(
                                title: "Active Syncs",
                                value: "\(appState.syncConfigurations.filter(\.isEnabled).count)"
                            )
                            StatBox(
                                title: "Total Syncs",
                                value: "\(appState.syncConfigurations.count)"
                            )
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Actions
                    VStack(spacing: 12) {
                        Button(action: { showSignOutConfirmation = true }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    // Not signed in
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)

                        Text("Not Signed In")
                            .font(.headline)

                        Text("Sign in with your Google account to start syncing sheets")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button(action: signIn) {
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("Sign in with Google")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 350, height: 400)
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                appState.signOut()
                dismiss()
            }
        } message: {
            Text("Your syncs will be paused until you sign in again.")
        }
    }

    private var initials: String {
        guard let email = appState.userEmail else { return "?" }
        let parts = email.split(separator: "@").first ?? ""
        let words = parts.split(separator: ".")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(parts.prefix(2)).uppercased()
    }

    private func signIn() {
        Task {
            do {
                try await appState.signIn()
            } catch {
                Logger.shared.error("Sign in failed: \(error)")
            }
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    AccountManagementView()
        .environmentObject(AppState.shared)
}
