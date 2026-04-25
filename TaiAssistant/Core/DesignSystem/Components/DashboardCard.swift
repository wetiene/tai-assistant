import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var trailingActionTitle: String? = nil
    var trailingAction: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        PrimaryCard(cornerRadius: 24) {
            CardHeader(
                title: title,
                icon: icon,
                tint: tint,
                trailingActionTitle: trailingActionTitle,
                trailingAction: trailingAction
            )
            content
        }
    }
}

struct CardHeader: View {
    let title: String
    let icon: String
    let tint: Color
    var trailingActionTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            IconBadge(icon: icon, tint: tint)
            Text(title)
                .dashboardPrimaryText(.title)
            Spacer(minLength: DSSpacing.sm)
            if let trailingActionTitle, let trailingAction {
                Button(trailingActionTitle, action: trailingAction)
                    .buttonStyle(.plain)
                    .dashboardSecondaryText()
            }
        }
    }
}

struct IconBadge: View {
    let icon: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

enum DashboardTextStyle {
    case title
    case body
}

private struct DashboardPrimaryTextModifier: ViewModifier {
    let style: DashboardTextStyle

    func body(content: Content) -> some View {
        switch style {
        case .title:
            content
                .font(.headline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
        case .body:
            content
                .font(.body.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
        }
    }
}

private struct DashboardSecondaryTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundStyle(DSColor.textSecondary)
    }
}

extension View {
    func dashboardPrimaryText(_ style: DashboardTextStyle) -> some View {
        modifier(DashboardPrimaryTextModifier(style: style))
    }

    func dashboardSecondaryText() -> some View {
        modifier(DashboardSecondaryTextModifier())
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
    var isPriority: Bool = false

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
                    .foregroundStyle(remaining < 0 ? DSColor.coralEnd : DSColor.textSecondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let fill = max(8, width * progress)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(isPriority ? 0.2 : 0.14))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(isPriority ? 0.75 : 0.55), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fill)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(consumed)g consumed")
                Spacer()
                Text("\(target)g target")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(DSColor.textSecondary)
        }
        .padding(.vertical, isPriority ? DSSpacing.xs : 0)
        .padding(.horizontal, isPriority ? DSSpacing.xs : 0)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPriority ? tint.opacity(0.05) : .clear)
        )
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
