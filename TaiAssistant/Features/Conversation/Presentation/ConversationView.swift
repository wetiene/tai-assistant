import SwiftUI
import UIKit

struct ConversationView: View {
    @Bindable var viewModel: ConversationViewModel

    @State private var isCameraPresented = false
    @State private var isConsentPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ConversationMessageListView(
                store: viewModel.store,
                isProcessing: viewModel.isProcessing,
                reduceMotion: reduceMotion,
                onQuickAction: { viewModel.handleQuickAction($0) },
                onMealCardAction: { action, cardID in
                    viewModel.handleMealCardAction(action, cardID: cardID)
                }
            )
            ConversationComposerHost(
                store: viewModel.store,
                isBusy: viewModel.isProcessing,
                onCamera: {
                    viewModel.handleQuickAction(
                        ConversationQuickAction(
                            id: MealCapabilityID.QuickAction.takePhoto,
                            title: "Take Photo",
                            systemImage: "camera.fill"
                        )
                    )
                },
                onClearPhoto: { viewModel.clearPendingPhoto() },
                onSend: {
                    Task { await viewModel.sendComposer() }
                },
                onTextChange: { viewModel.updateComposerText($0) }
            )
        }
        .background(DSColor.background.ignoresSafeArea())
        .onAppear {
            viewModel.startIfNeeded()
        }
        .onChange(of: viewModel.needsCamera) { _, needsCamera in
            if needsCamera {
                isCameraPresented = true
                viewModel.dismissCameraRequest()
            }
        }
        .onChange(of: viewModel.needsAIConsent) { _, needsConsent in
            if needsConsent {
                isConsentPresented = true
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CheckInCameraView { image in
                if let data = CheckInPhotoUploadPreprocessor.prepareMealUploadJPEG(from: image) {
                    viewModel.handleCapturedPhoto(data)
                } else {
                    viewModel.errorMessage = "Could not process this photo. Please try again."
                }
                isCameraPresented = false
            }
        }
        .sheet(isPresented: $isConsentPresented) {
            AIDataProcessingConsentSheet(
                onAccept: {
                    isConsentPresented = false
                    viewModel.acceptConsent()
                },
                onDecline: {
                    isConsentPresented = false
                    viewModel.declineConsent()
                }
            )
        }
        .alert("Tai", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if !presented { viewModel.errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

/// Observes message/history state only — composer keystrokes must not rebuild this tree.
private struct ConversationMessageListView: View {
    @Bindable var store: ConversationSessionStore
    var isProcessing: Bool
    var reduceMotion: Bool
    var onQuickAction: (ConversationQuickAction) -> Void
    var onMealCardAction: (MealCapabilityID.CardAction, UUID) -> Void

    var body: some View {
        let messages = store.active.messages
        let quickActions = store.active.activeQuickActions

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(messages) { message in
                        ConversationMessageRenderer(
                            message: message,
                            onQuickAction: onQuickAction,
                            onMealCardAction: onMealCardAction
                        )
                        .id(message.id)
                    }

                    if isProcessing {
                        HStack(spacing: DSSpacing.sm) {
                            ProgressView()
                            Text("Tai is thinking…")
                                .font(.subheadline)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        .padding(.horizontal, DSSpacing.lg)
                        .accessibilityLabel("Tai is thinking")
                        .id("thinking")
                    }

                    if !quickActions.isEmpty,
                       messages.last?.quickActions == nil {
                        ConversationQuickActionsRow(
                            actions: quickActions,
                            isEnabled: !isProcessing,
                            onSelect: onQuickAction
                        )
                        .id("quick-actions")
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                restoreScrollPosition(proxy: proxy, messages: messages)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, messages: messages, isProcessing: isProcessing)
            }
            .onChange(of: isProcessing) { _, _ in
                scrollToBottom(proxy: proxy, messages: messages, isProcessing: isProcessing)
            }
        }
    }

    private func restoreScrollPosition(proxy: ScrollViewProxy, messages: [ConversationMessage]) {
        let target = store.active.scrollAnchorMessageID ?? messages.last?.id
        guard let target else { return }
        if reduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private func scrollToBottom(
        proxy: ScrollViewProxy,
        messages: [ConversationMessage],
        isProcessing: Bool
    ) {
        let scroll = {
            if isProcessing {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }

        if reduceMotion {
            scroll()
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                scroll()
            }
        }
    }
}

/// Observes composer draft only.
private struct ConversationComposerHost: View {
    @Bindable var store: ConversationSessionStore
    var isBusy: Bool
    var onCamera: () -> Void
    var onClearPhoto: () -> Void
    var onSend: () -> Void
    var onTextChange: (String) -> Void

    var body: some View {
        ConversationComposerView(
            text: Binding(
                get: { store.composerDraft.text },
                set: onTextChange
            ),
            pendingPhoto: store.composerDraft.pendingPhotoJPEG,
            isSendEnabled: store.composerDraft.isSendEnabled,
            isBusy: isBusy,
            onCamera: onCamera,
            onClearPhoto: onClearPhoto,
            onSend: onSend
        )
    }
}
