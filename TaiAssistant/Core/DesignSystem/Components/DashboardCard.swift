import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        PrimaryCard(cornerRadius: 22) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
            }

            content
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: normalizedProgress)
                .stroke(
                    AngularGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0.65)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

struct MacroProgressRow: View {
    let label: String
    let consumed: Int
    let target: Int
    let tint: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(Double(consumed) / Double(target), 0), 1)
    }

    private var remaining: Int {
        target - consumed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Text("\(max(remaining, 0))g left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(remaining < 0 ? .red : DSColor.textSecondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let fill = max(8, width * progress)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.15))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.6), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fill)
                }
            }
            .frame(height: 10)

            Text("\(consumed)g / \(target)g")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DSColor.textSecondary)
        }
    }
}

struct MacroRemainingRow: View {
    let label: String
    let remaining: Int
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Spacer()
            Text("\(remaining) \(unit)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(remaining < 0 ? .red : DSColor.textSecondary)
        }
    }
}
