import SwiftUI

struct MealEstimateCardView: View {
    let payload: MealEstimateCardPayload
    var isInteractive: Bool
    var onAction: (MealCapabilityID.CardAction) -> Void
    var onLoggingDayChange: (Date) -> Void

    @State private var isDatePickerPresented = false
    @State private var pickerDraftDate = Date.now

    private var draft: MealEstimateSnapshot { payload.draft }
    private var loggingDay: NutritionDay { draft.nutritionDay }
    private var loggingDateLabel: String {
        MealEstimateCardFormatting.loggingDateLabel(for: loggingDay)
    }
    private var canEditLoggingDay: Bool {
        isInteractive && !payload.isLogged
    }

    var body: some View {
        PrimaryCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(draft.timingRaw.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 4)
                        .background(DSColor.warmSurface)
                        .clipShape(Capsule())
                    Spacer()
                    if payload.isLogged {
                        Label("Logged", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColor.coralEnd)
                    }
                }

                Text(draft.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DSSpacing.sm) {
                    macroPill(title: "kcal", value: "\(draft.calories)")
                    macroPill(title: "P", value: "\(draft.proteinGrams)g")
                    macroPill(title: "C", value: "\(draft.carbsGrams)g")
                    macroPill(title: "F", value: "\(draft.fatGrams)g")
                }

                Text("Confidence \(Int((draft.confidence * 100).rounded()))%")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)

                if draft.confidence < CheckInAIConfidence.mealAmbiguityThreshold {
                    Text("This estimate is less certain — worth a quick check.")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }

                loggingDateRow

                if isInteractive && !payload.isLogged {
                    actions
                }
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal estimate, \(draft.label), \(draft.calories) calories")
        .sheet(isPresented: $isDatePickerPresented) {
            HomeNutritionDayPickerSheet(
                selectedDate: $pickerDraftDate,
                maximumDate: .now,
                onCancel: { isDatePickerPresented = false },
                onConfirm: {
                    onLoggingDayChange(pickerDraftDate)
                    isDatePickerPresented = false
                }
            )
        }
    }

    @ViewBuilder
    private var loggingDateRow: some View {
        if canEditLoggingDay {
            Button {
                pickerDraftDate = loggingDay.start
                isDatePickerPresented = true
            } label: {
                loggingDateLabelContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Logging date, \(loggingDateLabel)")
            .accessibilityHint("Opens date picker to change which day this meal is logged to")
        } else {
            loggingDateLabelContent
                .accessibilityLabel("Logging date, \(loggingDateLabel)")
        }
    }

    private var loggingDateLabelContent: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
            Text(loggingDateLabel)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if canEditLoggingDay {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary.opacity(0.8))
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .padding(.horizontal, DSSpacing.sm)
        .background(DSColor.warmSurface.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Button {
                    onAction(.looksRight)
                } label: {
                    Text("Looks right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(DSColor.coralEnd)
                .accessibilityHint("Accept this estimate")

                Button {
                    onAction(.changeSomething)
                } label: {
                    Text("Change something")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Correct this estimate in the conversation")
            }

            if payload.showsLogMeal {
                Button {
                    onAction(.logMeal)
                } label: {
                    Label("Log Meal", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CoralGradientButtonStyle())
                .accessibilityHint("Save this meal")
            }
        }
        .padding(.top, DSSpacing.xs)
    }

    private func macroPill(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColor.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}
