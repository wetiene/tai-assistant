import SwiftUI

struct HomeDayNavigationBar: View {
    let title: String
    let canGoForward: Bool
    let showsTodayShortcut: Bool
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onSelectDate: () -> Void
    let onSelectToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                dayStepButton(
                    systemImage: "chevron.left",
                    label: "Previous day",
                    action: onPreviousDay
                )

                Button(action: onSelectDate) {
                    HStack(spacing: DSSpacing.xs) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColor.coralEnd)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.sm)
                    .padding(.horizontal, DSSpacing.md)
                    .background(DSColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DSColor.cardStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Selected day, \(title)")
                .accessibilityHint("Opens date picker")

                dayStepButton(
                    systemImage: "chevron.right",
                    label: "Next day",
                    isEnabled: canGoForward,
                    action: onNextDay
                )
            }

            if showsTodayShortcut {
                Button(action: onSelectToday) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, 6)
                        .background(DSColor.coralEnd.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to today")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func dayStepButton(
        systemImage: String,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? DSColor.textPrimary : DSColor.textSecondary.opacity(0.45))
                .frame(width: 44, height: 44)
                .background(DSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DSColor.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

struct HomeNutritionDayPickerSheet: View {
    @Binding var selectedDate: Date
    let maximumDate: Date
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                DatePicker(
                    "Nutrition day",
                    selection: $selectedDate,
                    in: ...maximumDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .accessibilityLabel("Nutrition day")

                Text("Future days can’t be selected.")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.lg)
            .navigationTitle("Choose a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onConfirm)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
