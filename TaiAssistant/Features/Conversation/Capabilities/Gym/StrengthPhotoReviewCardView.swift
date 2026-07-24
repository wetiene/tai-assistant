import SwiftUI

struct StrengthPhotoReviewCardView: View {
    let payload: StrengthPhotoReviewCardPayload
    var isInteractive: Bool
    var onApply: (StrengthPhotoReviewCardPayload) -> Void
    var onDismiss: () -> Void

    @State private var selectedExerciseID: String?
    @State private var selectedExerciseName: String?

    private var resolvedExerciseID: String? {
        selectedExerciseID ?? payload.detectedExerciseID
    }

    private var resolvedExerciseName: String? {
        selectedExerciseName ?? payload.detectedExerciseName
    }

    private var requiresExerciseSelection: Bool {
        payload.detectedExerciseID == nil
            && payload.interpretation.exerciseCandidates.count > 1
    }

    private var canApply: Bool {
        resolvedExerciseID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("Photo review")
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if payload.photoCount > 1 {
                    Text("\(payload.photoCount) photos")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }

            if !payload.evidenceAttachmentIDs.isEmpty {
                evidenceThumbnails
            }

            exerciseSection
            weightSection

            if let name = resolvedExerciseName,
               payload.suggestedWeight == nil,
               payload.interpretation.detectedWeight == nil {
                Text("I identified the \(name), but I couldn't read the selected weight. You can enter it manually.")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            if requiresExerciseSelection, isInteractive, !payload.isApplied {
                Text("Choose the planned exercise that matches this machine.")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            if !payload.interpretation.limitations.isEmpty {
                ForEach(payload.interpretation.limitations, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }

            if isInteractive, !payload.isApplied {
                HStack(spacing: DSSpacing.sm) {
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("strength.conversation.dismissPhotoReview")
                    Button(action: applySelection) {
                        Text("Apply to Workout")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DSColor.coralEnd)
                    .disabled(!canApply)
                    .accessibilityIdentifier("strength.conversation.applyPhotoReview")
                }
            } else if payload.isApplied {
                Label("Applied — review values before confirming a set", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(DSSpacing.md)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DSColor.cardStroke, lineWidth: 1)
        )
        .frame(maxWidth: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strength.conversation.photoReview")
        .onAppear {
            selectedExerciseID = payload.detectedExerciseID
            selectedExerciseName = payload.detectedExerciseName
        }
    }

    @ViewBuilder
    private var exerciseSection: some View {
        if requiresExerciseSelection, isInteractive, !payload.isApplied {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Exercise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                ForEach(payload.interpretation.exerciseCandidates, id: \.exerciseID) { candidate in
                    Button {
                        selectedExerciseID = candidate.exerciseID
                        selectedExerciseName = candidate.displayName
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayName)
                                    .foregroundStyle(DSColor.textPrimary)
                                Text(candidate.reason)
                                    .font(.caption2)
                                    .foregroundStyle(DSColor.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if resolvedExerciseID == candidate.exerciseID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DSColor.coralEnd)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let name = resolvedExerciseName, !name.isEmpty {
            LabeledContent("Exercise", value: name)
        } else {
            Text("Could not identify the exercise from these photos.")
                .font(.subheadline)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    @ViewBuilder
    private var weightSection: some View {
        if let weight = payload.suggestedWeight {
            LabeledContent(
                "Weight",
                value: "\(weight.formattedStrengthWeight) \(payload.weightUnit)"
            )
        } else if resolvedExerciseID != nil {
            LabeledContent("Weight") {
                Text("Not detected")
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("strength.conversation.photoReview.weightNotDetected")
            }
        }
    }

    private func applySelection() {
        var updated = payload
        updated.detectedExerciseID = resolvedExerciseID
        updated.detectedExerciseName = resolvedExerciseName
        onApply(updated)
    }

    @ViewBuilder
    private var evidenceThumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(payload.evidenceAttachmentIDs, id: \.self) { attachmentID in
                    let attachment = ConversationAttachment(id: attachmentID, kind: .photoJPEGFile)
                    if let image = ConversationImageCache.image(id: attachmentID, loadData: {
                        ConversationAttachmentStore.shared.resolvedJPEGData(for: attachment)
                    }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel("Submitted gym photo")
                    }
                }
            }
        }
    }
}
