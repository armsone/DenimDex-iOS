import Photos
import SwiftUI
import UIKit

/// StarManager의 검증된 연속 촬영 카메라를 DenimDex에 맞게 이식했다.
struct CameraCaptureView: UIViewControllerRepresentable {
    let maxCount: Int
    let currentCount: Int
    let onFinish: ([Data]) -> Void
    let onPhotoLibrarySaveIssue: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.cameraFlashMode = .off
        picker.showsCameraControls = false
        picker.delegate = context.coordinator
        picker.cameraOverlayView = context.coordinator.makeOverlay(for: picker)
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        private weak var picker: UIImagePickerController?
        private weak var countLabel: UILabel?
        private weak var doneButton: UIButton?
        private weak var cancelButton: UIButton?
        private weak var shutterButton: UIButton?
        private weak var flipButton: UIButton?
        private weak var flashButton: UIButton?
        private var pendingPhotos: [Data] = []
        private var isCapturing = false
        private var finishRequested = false
        private var isCancelled = false
        private var didFinish = false
        private var didReportSaveIssue = false

        init(parent: CameraCaptureView) { self.parent = parent }

        func makeOverlay(for picker: UIImagePickerController) -> UIView {
            self.picker = picker
            let overlay = CameraOverlayView(frame: picker.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            let done = textButton("완료", action: #selector(finishTapped))
            done.accessibilityLabel = "촬영 완료"
            done.accessibilityHint = "찍은 사진을 촬영 순서대로 추가하고 카메라를 닫습니다"
            doneButton = done

            let cancel = textButton("취소", action: #selector(cancelTapped))
            cancel.accessibilityLabel = "촬영 취소"
            cancelButton = cancel

            let label = UILabel()
            label.textColor = .white
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textAlignment = .center
            label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            label.layer.cornerRadius = 14
            label.layer.masksToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false
            countLabel = label
            updateLabel()

            let shutter = UIButton(type: .custom)
            shutter.backgroundColor = .white
            shutter.layer.cornerRadius = 36
            shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            shutter.layer.borderWidth = 6
            shutter.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
            shutter.translatesAutoresizingMaskIntoConstraints = false
            shutter.accessibilityLabel = "사진 촬영"
            shutterButton = shutter

            let flip = iconButton("camera.rotate.fill", label: "카메라 전환", action: #selector(flipTapped))
            flip.isHidden = !Self.canFlipCamera
            flipButton = flip

            let flash = iconButton("bolt.slash.fill", label: "플래시 켜기", action: #selector(flashTapped))
            flash.isHidden = !UIImagePickerController.isFlashAvailable(for: picker.cameraDevice)
            flashButton = flash

            [done, cancel, label, shutter, flip, flash].forEach(overlay.addSubview)
            NSLayoutConstraint.activate([
                done.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 12),
                done.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                cancel.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 12),
                cancel.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: done.centerYAnchor),
                label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
                label.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
                shutter.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                shutter.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                shutter.widthAnchor.constraint(equalToConstant: 72),
                shutter.heightAnchor.constraint(equalTo: shutter.widthAnchor),
                flip.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
                flip.trailingAnchor.constraint(equalTo: shutter.leadingAnchor, constant: -42),
                flip.widthAnchor.constraint(equalToConstant: 48),
                flip.heightAnchor.constraint(equalTo: flip.widthAnchor),
                flash.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
                flash.leadingAnchor.constraint(equalTo: shutter.trailingAnchor, constant: 42),
                flash.widthAnchor.constraint(equalToConstant: 48),
                flash.heightAnchor.constraint(equalTo: flash.widthAnchor)
            ])
            return overlay
        }

        private func textButton(_ title: String, action: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            button.layer.cornerRadius = 18
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: action, for: .touchUpInside)
            return button
        }

        private func iconButton(_ name: String, label: String, action: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: name), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            button.layer.cornerRadius = 24
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside)
            return button
        }

        private func updateLabel() {
            let count = parent.currentCount + pendingPhotos.count
            countLabel?.text = "  \(count)/\(parent.maxCount)  "
            countLabel?.accessibilityLabel = "사진 \(count)장, 최대 \(parent.maxCount)장"
        }

        @objc private func captureTapped() {
            guard !isCapturing, !finishRequested, !isCancelled,
                  parent.currentCount + pendingPhotos.count < parent.maxCount,
                  let picker else { return }
            isCapturing = true
            updateControls()
            picker.takePicture()
        }

        @objc private func finishTapped() {
            guard !isCancelled, !didFinish else { return }
            if isCapturing {
                finishRequested = true
                updateControls()
            } else { finish() }
        }

        @objc private func cancelTapped() {
            guard !didFinish else { return }
            isCancelled = true
            pendingPhotos.removeAll()
            parent.dismiss()
        }

        @objc private func flipTapped() {
            guard !isCapturing, !finishRequested, let picker else { return }
            picker.cameraDevice = picker.cameraDevice == .rear ? .front : .rear
            picker.cameraFlashMode = .off
            updateFlashButton()
        }

        @objc private func flashTapped() {
            guard !isCapturing, !finishRequested, let picker,
                  UIImagePickerController.isFlashAvailable(for: picker.cameraDevice) else { return }
            picker.cameraFlashMode = picker.cameraFlashMode == .off ? .on : .off
            updateFlashButton()
        }

        private func updateFlashButton() {
            guard let picker, let flashButton else { return }
            let available = UIImagePickerController.isFlashAvailable(for: picker.cameraDevice)
            flashButton.isHidden = !available
            let on = available && picker.cameraFlashMode == .on
            flashButton.setImage(UIImage(systemName: on ? "bolt.fill" : "bolt.slash.fill"), for: .normal)
            flashButton.accessibilityLabel = on ? "플래시 끄기" : "플래시 켜기"
        }

        private func updateControls() {
            let busy = isCapturing || finishRequested || isCancelled || didFinish
            doneButton?.isEnabled = !isCancelled && !didFinish
            cancelButton?.isEnabled = !isCancelled && !didFinish
            shutterButton?.isEnabled = !busy && parent.currentCount + pendingPhotos.count < parent.maxCount
            flipButton?.isEnabled = !busy
            flashButton?.isEnabled = !busy
        }

        private func finish() {
            guard !isCancelled, !didFinish else { return }
            didFinish = true
            updateControls()
            parent.onFinish(pendingPhotos)
            pendingPhotos.removeAll()
            parent.dismiss()
        }

        private static var canFlipCamera: Bool {
            UIImagePickerController.isCameraDeviceAvailable(.rear) &&
                UIImagePickerController.isCameraDeviceAvailable(.front)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.92)
            if let data { saveToLibrary(data) }
            guard !isCancelled, !didFinish else { return }
            if let data, parent.currentCount + pendingPhotos.count < parent.maxCount { pendingPhotos.append(data) }
            isCapturing = false
            updateLabel()
            updateControls()
            if finishRequested { finish() }
        }

        private func saveToLibrary(_ data: Data) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                guard status == .authorized || status == .limited else {
                    Task { @MainActor in self?.reportSaveIssueOnce() }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }) { success, _ in
                    guard !success else { return }
                    Task { @MainActor in self?.reportSaveIssueOnce() }
                }
            }
        }

        private func reportSaveIssueOnce() {
            guard !didReportSaveIssue else { return }
            didReportSaveIssue = true
            parent.onPhotoLibrarySaveIssue()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancelTapped() }
    }
}

private final class CameraOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
