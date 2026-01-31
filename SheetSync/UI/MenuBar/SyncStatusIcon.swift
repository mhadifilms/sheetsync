import SwiftUI

struct SyncStatusIcon: View {
    let status: SyncStatus

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch status {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle"
        case .rateLimited:
            return "clock.arrow.circlepath"
        case .paused:
            return "pause.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .idle:
            return .primary
        case .syncing:
            return .blue
        case .error:
            return .red
        case .rateLimited:
            return .orange
        case .paused:
            return .secondary
        }
    }
}

struct AnimatedSyncIcon: View {
    let isAnimating: Bool

    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(rotation))
            .onAppear {
                if isAnimating {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                } else {
                    withAnimation {
                        rotation = 0
                    }
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        SyncStatusIcon(status: .idle)
        SyncStatusIcon(status: .syncing)
        SyncStatusIcon(status: .error)
        SyncStatusIcon(status: .rateLimited)
        SyncStatusIcon(status: .paused)
    }
    .padding()
}
