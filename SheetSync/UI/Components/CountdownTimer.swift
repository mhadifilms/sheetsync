import SwiftUI

struct CountdownTimer: View {
    let targetDate: Date

    @State private var timeRemaining: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedTime)
            .monospacedDigit()
            .onAppear {
                updateTimeRemaining()
            }
            .onReceive(timer) { _ in
                updateTimeRemaining()
            }
    }

    private var formattedTime: String {
        if timeRemaining <= 0 {
            return "now"
        }

        let seconds = Int(timeRemaining)

        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes < 60 {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        return String(format: "%d:%02d:%02d", hours, remainingMinutes, remainingSeconds)
    }

    private func updateTimeRemaining() {
        timeRemaining = max(0, targetDate.timeIntervalSinceNow)
    }
}

struct CountdownProgressRing: View {
    let progress: Double  // 0.0 to 1.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CountdownTimer(targetDate: Date().addingTimeInterval(45))
        CountdownTimer(targetDate: Date().addingTimeInterval(125))
        CountdownTimer(targetDate: Date().addingTimeInterval(3725))

        CountdownProgressRing(progress: 0.75)
            .frame(width: 40, height: 40)
    }
    .padding()
}
