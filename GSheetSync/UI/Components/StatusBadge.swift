import SwiftUI

struct StatusBadge: View {
    let status: SyncStatus
    let showLabel: Bool

    init(status: SyncStatus, showLabel: Bool = true) {
        self.status = status
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if showLabel {
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.horizontal, showLabel ? 8 : 4)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        case .rateLimited: return .orange
        case .paused: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .idle: return "Synced"
        case .syncing: return "Syncing"
        case .error: return "Error"
        case .rateLimited: return "Limited"
        case .paused: return "Paused"
        }
    }
}

struct AnimatedStatusBadge: View {
    let status: SyncStatus

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            if status == .syncing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                    .onAppear { isAnimating = true }
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            Text(statusLabel)
                .font(.caption)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        case .rateLimited: return .orange
        case .paused: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .idle: return "Synced"
        case .syncing: return "Syncing"
        case .error: return "Error"
        case .rateLimited: return "Limited"
        case .paused: return "Paused"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .idle)
        StatusBadge(status: .syncing)
        StatusBadge(status: .error)
        StatusBadge(status: .rateLimited)
        StatusBadge(status: .paused)

        Divider()

        StatusBadge(status: .idle, showLabel: false)
        StatusBadge(status: .error, showLabel: false)

        Divider()

        AnimatedStatusBadge(status: .syncing)
    }
    .padding()
}
