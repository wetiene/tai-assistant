import SwiftUI
import UIKit

struct ConversationComposerView: View {
    @Binding var text: String
    var pendingPhotos: [Data]
    var isSendEnabled: Bool
    var isBusy: Bool
    var onCamera: () -> Void
    var onRemovePhoto: (Int) -> Void
    var onClearPhotos: () -> Void
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            if !pendingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(Array(pendingPhotos.enumerated()), id: \.offset) { index, photo in
                            ZStack(alignment: .topTrailing) {
                                photoThumbnail(photo, index: index)
                                Button {
                                    onRemovePhoto(index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white, DSColor.destructiveCoral)
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, DSSpacing.sm)
                }
                HStack {
                    Text(pendingPhotos.count == 1 ? "Photo ready" : "\(pendingPhotos.count) photos ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    Button("Clear", action: onClearPhotos)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.destructiveCoral)
                }
                .padding(.horizontal, DSSpacing.sm)
            }

            HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                Button(action: onCamera) {
                    Image(systemName: "camera.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                        .frame(width: 44, height: 44)
                        .background(DSColor.warmSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel("Camera")
                .accessibilityHint("Take a photo")

                TextField("Message Tai…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(DSColor.cardStroke, lineWidth: 1)
                    )
                    .disabled(isBusy)
                    .accessibilityLabel("Message")
                    .accessibilityIdentifier("tai.composer.textField")

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSendEnabled && !isBusy ? Color.white : DSColor.textSecondary.opacity(0.5),
                            isSendEnabled && !isBusy ? DSColor.coralEnd : DSColor.warmSurface
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!isSendEnabled || isBusy)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("tai.composer.send")
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(.ultraThinMaterial)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isFocused = false
                } label: {
                    Label("Done", systemImage: "keyboard.chevron.compact.down")
                }
            }
        }
    }

    private func photoThumbnail(_ data: Data, index: Int) -> some View {
        let key = "composer-pending-\(index)-\(data.count)"
        return Group {
            if let image = ConversationImageCache.cached(key: key)
                ?? ConversationImageCache.image(key: key, data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
