import SwiftUI
import UIKit

struct ConversationView: View {
    @Bindable var viewModel: ConversationViewModel

    @State private var isCameraPresented = false
    @State private var isConsentPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(viewModel.conversation.messages) { message in
                        ConversationMessageRenderer(
                            message: message,
                            onQuickAction: { viewModel.handleQuickAction($0) },
                            onMealCardAction: { action, cardID in
                                viewModel.handleMealCardAction(action, cardID: cardID)
                            }
                        )
                        .id(message.id)
                    }

                    if viewModel.isProcessing {
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

                    if !viewModel.conversation.activeQuickActions.isEmpty,
                       viewModel.conversation.messages.last?.quickActions == nil {
                        ConversationQuickActionsRow(
                            actions: viewModel.conversation.activeQuickActions,
                            isEnabled: !viewModel.isProcessing
                        ) { action in
                            viewModel.handleQuickAction(action)
                        }
                        .id("quick-actions")
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                restoreScrollPosition(proxy: proxy)
            }
            .onChange(of: viewModel.conversation.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isProcessing) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .background(DSColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConversationComposerView(
                text: Binding(
                    get: { viewModel.conversation.composer.text },
                    set: { viewModel.updateComposerText($0) }
                ),
                pendingPhoto: viewModel.conversation.composer.pendingPhotoJPEG,
                isSendEnabled: viewModel.conversation.composer.isSendEnabled,
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
                }
            )
        }
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

    private func restoreScrollPosition(proxy: ScrollViewProxy) {
        let target = viewModel.conversation.scrollAnchorMessageID
            ?? viewModel.conversation.messages.last?.id
        guard let target else { return }
        if reduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let scroll = {
            if viewModel.isProcessing {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = viewModel.conversation.messages.last {
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
