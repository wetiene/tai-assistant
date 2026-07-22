import SwiftUI
import UIKit

struct ConversationQuickActionsRow: View {
    let actions: [ConversationQuickAction]
    var isEnabled: Bool = true
    var onSelect: (ConversationQuickAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(actions) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        HStack(spacing: DSSpacing.xs) {
                            if let systemImage = action.systemImage {
                                Image(systemName: systemImage)
                            }
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(DSColor.textPrimary)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.sm)
                        .background(DSColor.warmSurface)
                        .overlay(
                            Capsule()
                                .stroke(DSColor.cardStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.accessibilityHint ?? "")
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }
}

struct ConversationMessageRenderer: View {
    let message: ConversationMessage
    var onQuickAction: (ConversationQuickAction) -> Void
    var onMealCardAction: (MealCapabilityID.CardAction, UUID) -> Void
    var onMealCardLoggingDayChange: (UUID, Date) -> Void
    var onGymPlanTakePhoto: () -> Void
    var onGymPlanFinish: () -> Void
    var onGymManagePlans: () -> Void
    var onGymSetCardAction: (GymCapabilityID.CardAction, UUID, GymSetConfirmationCardPayload) -> Void
    var onGymSetDraftChange: (UUID, GymSetConfirmationCardPayload) -> Void
    var onWhy: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: bubbleAlignment, spacing: DSSpacing.xs) {
            if let text = message.text, !text.isEmpty {
                textBubble(text)
            }
            if let attachment = message.attachment {
                attachmentView(attachment)
            }
            if let card = message.card {
                cardView(card)
            }
            if let actions = message.quickActions, !actions.isEmpty {
                ConversationQuickActionsRow(actions: actions, onSelect: onQuickAction)
                    .padding(.top, DSSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityElement(children: .contain)
    }

    private var bubbleAlignment: HorizontalAlignment {
        message.actor == .user ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        message.actor == .user ? .trailing : .leading
    }

    @ViewBuilder
    private func textBubble(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(message.actor == .user ? Color.white : DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(message.actor == .user ? AnyShapeStyle(DSColor.coralGradient) : AnyShapeStyle(DSColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if message.actor != .user {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DSColor.cardStroke, lineWidth: 1)
                }
            }
            .frame(maxWidth: 320, alignment: frameAlignment)
            .accessibilityLabel(message.actor == .user ? "You" : "Tai")
            .accessibilityValue(text)
    }

    @ViewBuilder
    private func attachmentView(_ attachment: ConversationAttachment) -> some View {
        // Cache-first: never hit disk when the decoded UIImage is already retained.
        if let image = ConversationImageCache.image(id: attachment.id, loadData: {
            ConversationAttachmentStore.shared.resolvedJPEGData(for: attachment)
        }) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 220, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Meal photo")
        }
    }

    @ViewBuilder
    private func cardView(_ card: ConversationCard) -> some View {
        switch card.typeID {
        case MealCapabilityID.estimateCardType:
            if let payload = MealCardPayloadCache.payload(for: card) {
                MealEstimateCardView(
                    payload: payload,
                    isInteractive: card.isInteractive,
                    onAction: { action in
                        onMealCardAction(action, card.id)
                    },
                    onLoggingDayChange: { date in
                        onMealCardLoggingDayChange(card.id, date)
                    }
                )
            }
        case LiveTaiEvidencePayload.cardTypeID:
            // Why disclosure control — not a structured coaching card.
            if card.isInteractive {
                Button {
                    onWhy?()
                } label: {
                    Label("Why?", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Why Tai said this")
            }
        case GymCapabilityID.workoutPlanCardType:
            if let payload = GymWorkoutPlanCardCodec.decode(card.payload) {
                GymWorkoutPlanCardView(
                    payload: payload,
                    isInteractive: card.isInteractive,
                    onTakePhoto: onGymPlanTakePhoto,
                    onFinishWorkout: onGymPlanFinish,
                    onManagePlans: onGymManagePlans
                )
            }
        case GymCapabilityID.setConfirmCardType:
            if let payload = GymSetConfirmationCardCodec.decode(card.payload) {
                GymSetConfirmationCardView(
                    payload: payload,
                    isInteractive: card.isInteractive,
                    onDraftChange: { updated in
                        onGymSetDraftChange(card.id, updated)
                    },
                    onAction: { action, updated in
                        onGymSetCardAction(action, card.id, updated)
                    }
                )
            }
        default:
            EmptyView()
        }
    }
}

