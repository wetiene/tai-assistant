import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CheckInCameraView: View {
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = CheckInCameraController()
    @State private var selectedLibraryItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CheckInCameraPreview(session: cameraController.session)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if cameraController.isPermissionDenied {
                cameraBlockedOverlay(
                    title: "Camera access is off",
                    detail: "Enable camera access in Settings to capture a check-in photo."
                )
            } else if cameraController.isUnavailable {
                cameraBlockedOverlay(
                    title: "Camera unavailable",
                    detail: "This device does not provide an active camera source."
                )
            }

            VStack {
                Spacer()

                HStack(alignment: .center) {
                    PhotosPicker(selection: $selectedLibraryItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        cameraController.capturePhoto { image in
                            onImagePicked(image)
                            dismiss()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 74, height: 74)
                            Circle()
                                .stroke(Color.black.opacity(0.25), lineWidth: 1.5)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(cameraController.isPermissionDenied || cameraController.isUnavailable)

                    Spacer()

                    Button {
                        cameraController.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(cameraController.isPermissionDenied || cameraController.isUnavailable)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xl)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.sm)
            .contentShape(Rectangle())
            .zIndex(1000)
        }
        .onAppear {
            cameraController.start()
        }
        .onDisappear {
            cameraController.stop()
        }
        .onChange(of: selectedLibraryItem) { _, item in
            guard let item else { return }
            Task {
                await loadLibraryImage(from: item)
            }
        }
    }

    @ViewBuilder
    private func cameraBlockedOverlay(title: String, detail: String) -> some View {
        VStack(spacing: DSSpacing.sm) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(DSSpacing.lg)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, DSSpacing.xl)
    }

    private func loadLibraryImage(from item: PhotosPickerItem) async {
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { return }
            await MainActor.run {
                onImagePicked(image)
                dismiss()
            }
        } catch {
            // Keep camera screen active on failed library load.
        }
    }
}

private struct CheckInCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
