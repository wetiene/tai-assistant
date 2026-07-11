import SwiftUI
import UIKit

struct ConversationComposerView: View {
    @Binding var text: String
    var pendingPhoto: Data?
    var isSendEnabled: Bool
    var isBusy: Bool
    var onCamera: () -> Void
    var onClearPhoto: () -> Void
    var onSend: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            if let pendingPhoto {
                HStack(spacing: DSSpacing.sm) {
                    photoThumbnail(pendingPhoto)
                    Text("Photo ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    Button("Remove", action: onClearPhoto)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.destructiveCoral)
                }
                .padding(.horizontal, DSSpacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Photo attached, ready to send")
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
                .accessibilityHint("Take a meal photo")

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

    private func photoThumbnail(_ data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
