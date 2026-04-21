import AVFoundation
import UIKit

final class CheckInCameraController: NSObject, ObservableObject {
    @Published var isPermissionDenied = false
    @Published var isUnavailable = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "tai.checkin.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var pendingCapture: ((UIImage) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureIfNeededAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isPermissionDenied = !granted
                }
                if granted {
                    self.configureIfNeededAndRun()
                }
            }
        default:
            isPermissionDenied = true
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(onCapture: @escaping (UIImage) -> Void) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        pendingCapture = onCapture
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let input = self.currentInput else { return }
            let nextPosition: AVCaptureDevice.Position = input.device.position == .back ? .front : .back
            guard let nextDevice = self.cameraDevice(for: nextPosition) else { return }
            do {
                let nextInput = try AVCaptureDeviceInput(device: nextDevice)
                self.session.beginConfiguration()
                self.session.removeInput(input)
                if self.session.canAddInput(nextInput) {
                    self.session.addInput(nextInput)
                    self.currentInput = nextInput
                } else {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
            } catch {
                // Keep the current camera if switching fails.
            }
        }
    }

    private func configureIfNeededAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.currentInput == nil {
                self.configureSession()
            }
            guard self.currentInput != nil else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()
        }

        guard let backCamera = cameraDevice(for: .back) else {
            DispatchQueue.main.async {
                self.isUnavailable = true
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.isUnavailable = true
                }
                return
            }
            session.addInput(input)
            currentInput = input
        } catch {
            DispatchQueue.main.async {
                self.isUnavailable = true
            }
            return
        }

        guard session.canAddOutput(photoOutput) else {
            DispatchQueue.main.async {
                self.isUnavailable = true
            }
            return
        }
        session.addOutput(photoOutput)
    }

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

extension CheckInCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pendingCapture?(image)
            self?.pendingCapture = nil
        }
    }
}
