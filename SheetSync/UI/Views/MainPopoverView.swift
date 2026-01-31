import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .opacity(0.3)

            if appState.isAuthenticated {
                if appState.syncConfigurations.isEmpty {
                    emptyStateView
                } else {
                    SyncListView()
                        .frame(minHeight: 120, maxHeight: 280)
                }

                Divider()
                    .opacity(0.3)

                footerView
            } else {
                signInView
            }
        }
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func openAddSyncWindow() {
        WindowManager.shared.openWindow(
            id: "add-sync",
            title: "Add Sync",
            content: AddSyncView().environmentObject(appState),
            size: NSSize(width: 520, height: 580)
        )
    }

    private func openSettingsWindow() {
        WindowManager.shared.openWindow(
            id: "settings",
            title: "Settings",
            content: GlobalSettingsView().environmentObject(appState),
            size: NSSize(width: 420, height: 380)
        )
    }

    private func openBackupsWindow() {
        WindowManager.shared.openWindow(
            id: "backups",
            title: "Backups",
            content: BackupBrowserView().environmentObject(appState),
            size: NSSize(width: 520, height: 420)
        )
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            // App icon with sync animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 36, height: 36)

                LucideIcon(AppIcon.table, size: 18, color: .green)
                    .rotationEffect(.degrees(appState.overallStatus == .syncing ? 360 : 0))
                    .animation(
                        appState.overallStatus == .syncing
                            ? .linear(duration: 2).repeatForever(autoreverses: false)
                            : .default,
                        value: appState.overallStatus
                    )
            }

            Text("sheetsync")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            if appState.isAuthenticated {
                Menu {
                    Button {
                        openSettingsWindow()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }

                    Button {
                        openBackupsWindow()
                    } label: {
                        Label("Backups", systemImage: "clock.arrow.circlepath")
                    }

                    Divider()

                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Divider()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            LucideIcon(AppIcon.plus, size: 44, color: .secondary.opacity(0.5))

            VStack(spacing: 4) {
                Text("No syncs yet")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Add a Google Sheet to start syncing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                openAddSyncWindow()
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(AppIcon.plus, size: 14)
                    Text("Add Sync")
                }
                .font(.subheadline)
                .fontWeight(.medium)
            }
            .buttonStyle(.glassPill(tint: .green))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var signInView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                LucideIcon(AppIcon.user, size: 36, color: .secondary)
                    .opacity(appState.authService.isAuthenticating ? 0.5 : 1)
            }

            VStack(spacing: 6) {
                Text("Sign in to get started")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Connect your Google account to sync sheets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                signIn()
            } label: {
                HStack(spacing: 8) {
                    if appState.authService.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        LucideIcon(AppIcon.logIn, size: 16)
                    }
                    Text("Sign in with Google")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
            }
            .buttonStyle(.glassPill(tint: .blue))
            .disabled(appState.authService.isAuthenticating)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            if let email = appState.userEmail {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)

                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                openAddSyncWindow()
            } label: {
                LucideIcon(AppIcon.plus, size: 16)
            }
            .buttonStyle(.glassIcon(size: 28))
            .help("Add new sync")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

#Preview {
    MainPopoverView()
        .environmentObject(AppState.shared)
}
