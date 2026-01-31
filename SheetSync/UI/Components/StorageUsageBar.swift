import SwiftUI

struct StorageUsageBar: View {
    let used: Int64
    let limit: Int64

    var progress: Double {
        guard limit > 0 else { return 0 }
        return min(1.0, Double(used) / Double(limit))
    }

    var progressColor: Color {
        if progress > 0.9 {
            return .red
        } else if progress > 0.75 {
            return .orange
        }
        return .blue
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

struct StorageUsageDetail: View {
    let used: Int64
    let limit: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Storage Used")
                    .font(.subheadline)
                Spacer()
                Text("\(formattedUsed) / \(formattedLimit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            StorageUsageBar(used: used, limit: limit)

            if used > limit * 90 / 100 {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Storage almost full. Consider increasing the limit or deleting old backups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }

    private var formattedLimit: String {
        if limit == Int64.max {
            return "Unlimited"
        }
        return ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
    }
}

#Preview {
    VStack(spacing: 20) {
        StorageUsageBar(used: 5_000_000_000, limit: 10_737_418_240)
            .frame(width: 200)

        StorageUsageBar(used: 8_000_000_000, limit: 10_737_418_240)
            .frame(width: 200)

        StorageUsageBar(used: 10_000_000_000, limit: 10_737_418_240)
            .frame(width: 200)

        Divider()

        StorageUsageDetail(used: 5_000_000_000, limit: 10_737_418_240)
            .frame(width: 300)

        StorageUsageDetail(used: 10_000_000_000, limit: 10_737_418_240)
            .frame(width: 300)
    }
    .padding()
}
