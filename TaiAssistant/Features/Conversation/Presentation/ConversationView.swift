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
                isMealBusy: viewModel.meal.isBusy,
                reduceMotion: reduceMotion,
                onQuickAction: { viewModel.handleQuickAction($0) },
                onMealCardAction: { action, cardID in
                    viewModel.handleMealCardAction(action, cardID: cardID)
                },
                onMealCardLoggingDayChange: { cardID, date in
                    viewModel.handleMealCardLoggingDayChange(cardID: cardID, selectedDate: date)
                },
                onWhy: {
                    viewModel.showLiveTaiWhy = true
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
                kind: viewModel.pendingConsentKind,
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
        .sheet(isPresented: Binding(
            get: { viewModel.showLiveTaiWhy },
            set: { presented in
                if !presented { viewModel.dismissLiveTaiWhy() }
            }
        )) {
            if let evidence = viewModel.latestLiveTaiEvidence {
                LiveTaiWhySheet(
                    evidence: evidence,
                    assistantName: viewModel.assistantName,
                    onDismiss: { viewModel.dismissLiveTaiWhy() }
                )
            }
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
    var isMealBusy: Bool
    var reduceMotion: Bool
    var onQuickAction: (ConversationQuickAction) -> Void
    var onMealCardAction: (MealCapabilityID.CardAction, UUID) -> Void
    var onMealCardLoggingDayChange: (UUID, Date) -> Void
    var onWhy: () -> Void

    private var isProcessing: Bool {
        if case .processing = store.active.activity { return true }
        return isMealBusy
    }

    var body: some View {
        let messages = store.active.messages
        let quickActions = store.active.activeQuickActions
        let processing = isProcessing

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(messages) { message in
                        ConversationMessageRenderer(
                            message: message,
                            onQuickAction: onQuickAction,
                            onMealCardAction: onMealCardAction,
                            onMealCardLoggingDayChange: onMealCardLoggingDayChange,
                            onWhy: onWhy
                        )
                        .id(message.id)
                    }

                    if processing {
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
                            isEnabled: !processing,
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
            // Auto-scroll only for transcript growth / processing — never for composer keystrokes.
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, isProcessing: processing)
            }
            .onChange(of: processing) { wasBusy, isBusyNow in
                // Scroll when thinking begins; avoid a second animated scroll when it ends
                // unless message count also changed (handled above).
                if isBusyNow && !wasBusy {
                    scrollToBottom(proxy: proxy, isProcessing: true)
                }
            }
        }
    }

    private func restoreScrollPosition(proxy: ScrollViewProxy, messages: [ConversationMessage]) {
        let target = store.active.scrollAnchorMessageID ?? messages.last?.id
        guard let target else { return }
        ConversationRuntimeProbe.recordScrollToBottom()
        if reduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, isProcessing: Bool) {
        ConversationRuntimeProbe.recordScrollToBottom()
        let scroll = {
            if isProcessing {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = store.active.messages.last {
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

/// Local `@State` owns the TextField so Observable draft updates do not recreate the editor
/// or destroy selection / cursor while typing.
private struct ConversationComposerHost: View {
    @Bindable var store: ConversationSessionStore
    var isBusy: Bool
    var onCamera: () -> Void
    var onClearPhoto: () -> Void
    var onSend: () -> Void
    var onTextChange: (String) -> Void

    @State private var localText: String = ""
    @State private var didSeedText = false

    private var isSendEnabled: Bool {
        let trimmed = localText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || store.composerDraft.pendingPhotoJPEG != nil
    }

    var body: some View {
        ConversationComposerView(
            text: $localText,
            pendingPhoto: store.composerDraft.pendingPhotoJPEG,
            isSendEnabled: isSendEnabled,
            isBusy: isBusy,
            onCamera: onCamera,
            onClearPhoto: onClearPhoto,
            onSend: onSend
        )
        .onAppear {
            guard !didSeedText else { return }
            localText = store.composerDraft.text
            didSeedText = true
        }
        .onChange(of: localText) { _, newValue in
            if newValue != store.composerDraft.text {
                onTextChange(newValue)
            }
        }
        .onChange(of: store.composerDraft.text) { _, external in
            // Sync clears / restores from the store without fighting in-progress edits
            // when values already match.
            if external != localText {
                localText = external
            }
        }
    }
}
