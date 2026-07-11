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
        switch attachment.kind {
        case .photoJPEG(let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Meal photo")
            }
        }
    }

    @ViewBuilder
    private func cardView(_ card: ConversationCard) -> some View {
        switch card.typeID {
        case MealCapabilityID.estimateCardType:
            if let payload = MealCardCodec.decode(card.payload) {
                MealEstimateCardView(
                    payload: payload,
                    isInteractive: card.isInteractive,
                    onAction: { action in
                        onMealCardAction(action, card.id)
                    }
                )
            }
        default:
            EmptyView()
        }
    }
}
