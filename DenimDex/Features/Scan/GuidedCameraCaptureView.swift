import Photos
import SwiftUI
import UIKit

/// 9단계 정밀 가이드 촬영을 위한 맞춤형 연속 촬영 카메라.
/// 상단에 현재 단계의 한국어 안내(초등학교 5학년 수준)를 띄우고,
/// 이전 단계·다시 찍기·건너뛰기 및 완료 검토로의 전환을 지원한다.
struct GuidedCameraCaptureView: UIViewControllerRepresentable {
    let preset: GuidedCapturePreset
    let initialSlotIndex: Int
    let initialSlots: [GuidedShotSlot]
    let onFinish: ([GuidedShotSlot]) -> Void
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
        let parent: GuidedCameraCaptureView
        private weak var picker: UIImagePickerController?

        private weak var stepBadgeLabel: UILabel?
        private weak var titleLabel: UILabel?
        private weak var instructionLabel: UILabel?
        private weak var guideImageView: UIImageView?
        private weak var doneButton: UIButton?
        private weak var previousButton: UIButton?
        private weak var skipButton: UIButton?
        private weak var shutterButton: UIButton?
        private weak var flipButton: UIButton?
        private weak var flashButton: UIButton?

        private var currentSlotIndex: Int
        private var workingSlots: [GuidedShotSlot]
        private var isCapturing = false
        private var finishRequested = false
        private var isCancelled = false
        private var didFinish = false
        private var didReportSaveIssue = false

        init(parent: GuidedCameraCaptureView) {
            self.parent = parent
            self.workingSlots = parent.initialSlots
            self.currentSlotIndex = min(max(0, parent.initialSlotIndex), parent.initialSlots.count - 1)
        }

        func makeOverlay(for picker: UIImagePickerController) -> UIView {
            self.picker = picker
            let overlay = GuidedOverlayContainerView(frame: picker.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // 상단 닫기/검토 버튼
            let done = textButton("검토로 이동", action: #selector(finishTapped))
            done.accessibilityLabel = "촬영 검토로 이동"
            doneButton = done

            // 상단 단계 뱃지
            let badge = UILabel()
            badge.textColor = .white
            badge.font = .systemFont(ofSize: 13, weight: .bold)
            badge.textAlignment = .center
            badge.backgroundColor = UIColor.black.withAlphaComponent(0.60)
            badge.layer.cornerRadius = 13
            badge.layer.masksToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            stepBadgeLabel = badge

            // 상단 HUD 안내 카드
            let hudCard = UIView()
            hudCard.backgroundColor = UIColor.black.withAlphaComponent(0.70)
            hudCard.layer.cornerRadius = 16
            hudCard.layer.masksToBounds = true
            hudCard.translatesAutoresizingMaskIntoConstraints = false

            let title = UILabel()
            title.textColor = .white
            title.font = .systemFont(ofSize: 16, weight: .bold)
            title.numberOfLines = 1
            title.translatesAutoresizingMaskIntoConstraints = false
            titleLabel = title

            let instruction = UILabel()
            instruction.textColor = UIColor.white.withAlphaComponent(0.90)
            instruction.font = .systemFont(ofSize: 13, weight: .medium)
            instruction.numberOfLines = 2
            instruction.translatesAutoresizingMaskIntoConstraints = false
            instructionLabel = instruction

            let guideImage = UIImageView()
            guideImage.contentMode = .scaleAspectFit
            guideImage.clipsToBounds = true
            guideImage.layer.cornerRadius = 10
            guideImage.translatesAutoresizingMaskIntoConstraints = false
            guideImageView = guideImage

            hudCard.addSubview(title)
            hudCard.addSubview(instruction)
            hudCard.addSubview(guideImage)

            NSLayoutConstraint.activate([
                title.topAnchor.constraint(equalTo: hudCard.topAnchor, constant: 10),
                title.leadingAnchor.constraint(equalTo: hudCard.leadingAnchor, constant: 14),
                title.trailingAnchor.constraint(equalTo: guideImage.leadingAnchor, constant: -10),
                instruction.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
                instruction.leadingAnchor.constraint(equalTo: hudCard.leadingAnchor, constant: 14),
                instruction.trailingAnchor.constraint(equalTo: guideImage.leadingAnchor, constant: -10),
                instruction.bottomAnchor.constraint(equalTo: hudCard.bottomAnchor, constant: -10),
                guideImage.trailingAnchor.constraint(equalTo: hudCard.trailingAnchor, constant: -14),
                guideImage.centerYAnchor.constraint(equalTo: hudCard.centerYAnchor),
                guideImage.widthAnchor.constraint(equalToConstant: 54),
                guideImage.heightAnchor.constraint(equalToConstant: 54)
            ])

            // 셔터 버튼
            let shutter = UIButton(type: .custom)
            shutter.backgroundColor = .white
            shutter.layer.cornerRadius = 36
            shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            shutter.layer.borderWidth = 6
            shutter.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
            shutter.translatesAutoresizingMaskIntoConstraints = false
            shutter.accessibilityLabel = "현재 샷 촬영"
            shutterButton = shutter

            // 이전 단계 버튼
            let prev = iconButton("chevron.backward", label: "이전 샷", action: #selector(previousTapped))
            previousButton = prev

            // 건너뛰기 버튼
            let skip = textButton("건너뛰기", action: #selector(skipTapped))
            skip.accessibilityLabel = "이 부위 건너뛰기"
            skipButton = skip

            // 플립 & 플래시
            let flip = iconButton("camera.rotate.fill", label: "카메라 전환", action: #selector(flipTapped))
            flip.isHidden = !Self.canFlipCamera
            flipButton = flip

            let flash = iconButton("bolt.slash.fill", label: "플래시 켜기", action: #selector(flashTapped))
            flash.isHidden = !UIImagePickerController.isFlashAvailable(for: picker.cameraDevice)
            flashButton = flash

            [done, badge, hudCard, prev, shutter, skip, flip, flash].forEach(overlay.addSubview)

            NSLayoutConstraint.activate([
                done.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 10),
                done.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                badge.centerYAnchor.constraint(equalTo: done.centerYAnchor),
                badge.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
                badge.heightAnchor.constraint(equalToConstant: 28),
                flash.centerYAnchor.constraint(equalTo: done.centerYAnchor),
                flash.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                flash.widthAnchor.constraint(equalToConstant: 38),
                flash.heightAnchor.constraint(equalTo: flash.widthAnchor),

                hudCard.topAnchor.constraint(equalTo: done.bottomAnchor, constant: 12),
                hudCard.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                hudCard.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),

                shutter.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                shutter.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                shutter.widthAnchor.constraint(equalToConstant: 72),
                shutter.heightAnchor.constraint(equalTo: shutter.widthAnchor),

                prev.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
                prev.trailingAnchor.constraint(equalTo: shutter.leadingAnchor, constant: -32),
                prev.widthAnchor.constraint(equalToConstant: 48),
                prev.heightAnchor.constraint(equalTo: prev.widthAnchor),

                skip.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
                skip.leadingAnchor.constraint(equalTo: shutter.leadingAnchor, constant: 28),
                skip.heightAnchor.constraint(equalToConstant: 44),

                flip.bottomAnchor.constraint(equalTo: hudCard.bottomAnchor),
                flip.trailingAnchor.constraint(equalTo: hudCard.trailingAnchor, constant: -8),
                flip.widthAnchor.constraint(equalToConstant: 36),
                flip.heightAnchor.constraint(equalTo: flip.widthAnchor)
            ])

            updateHUD()
            updateControls()
            return overlay
        }

        private func textButton(_ title: String, action: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.60)
            button.layer.cornerRadius = 18
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: action, for: .touchUpInside)
            return button
        }

        private func iconButton(_ name: String, label: String, action: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: name), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.60)
            button.layer.cornerRadius = 24
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside)
            return button
        }

        private func updateHUD() {
            guard workingSlots.indices.contains(currentSlotIndex) else { return }
            let slot = workingSlots[currentSlotIndex]
            let total = workingSlots.count
            stepBadgeLabel?.text = " \(currentSlotIndex + 1) / \(total) "
            titleLabel?.text = "\(currentSlotIndex + 1). \(slot.definition.title)"
            instructionLabel?.text = slot.definition.shortInstruction
            updateGuideImage(for: slot)
        }

        private func updateGuideImage(for slot: GuidedShotSlot) {
            guard let guideImageView else { return }
            if let imageName = slot.definition.referenceImageName, let image = UIImage(named: imageName) {
                guideImageView.image = image
                guideImageView.isHidden = false
            } else {
                guideImageView.isHidden = true
            }
        }

        private func updateControls() {
            let busy = isCapturing || finishRequested || isCancelled || didFinish
            doneButton?.isEnabled = !isCancelled && !didFinish
            shutterButton?.isEnabled = !busy
            previousButton?.isEnabled = !busy && currentSlotIndex > 0
            previousButton?.alpha = currentSlotIndex > 0 ? 1.0 : 0.4
            skipButton?.isEnabled = !busy
            flipButton?.isEnabled = !busy
            flashButton?.isEnabled = !busy
        }

        @objc private func captureTapped() {
            guard !isCapturing, !finishRequested, !isCancelled, let picker else { return }
            isCapturing = true
            updateControls()
            picker.takePicture()
        }

        @objc private func previousTapped() {
            guard !isCapturing, currentSlotIndex > 0 else { return }
            currentSlotIndex -= 1
            updateHUD()
            updateControls()
        }

        @objc private func skipTapped() {
            guard !isCapturing, workingSlots.indices.contains(currentSlotIndex) else { return }
            workingSlots[currentSlotIndex].isSkipped = true
            advanceOrFinish()
        }

        @objc private func finishTapped() {
            guard !isCancelled, !didFinish else { return }
            if isCapturing {
                finishRequested = true
                updateControls()
            } else {
                finish()
            }
        }

        @objc private func flipTapped() {
            guard !isCapturing, let picker else { return }
            picker.cameraDevice = picker.cameraDevice == .rear ? .front : .rear
            picker.cameraFlashMode = .off
            updateFlashButton()
        }

        @objc private func flashTapped() {
            guard !isCapturing, let picker,
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

        private func advanceOrFinish() {
            if currentSlotIndex + 1 < workingSlots.count {
                currentSlotIndex += 1
                updateHUD()
                updateControls()
            } else {
                finish()
            }
        }

        private func finish() {
            guard !isCancelled, !didFinish else { return }
            didFinish = true
            updateControls()
            parent.onFinish(workingSlots)
            parent.dismiss()
        }

        private static var canFlipCamera: Bool {
            UIImagePickerController.isCameraDeviceAvailable(.rear) &&
                UIImagePickerController.isCameraDeviceAvailable(.front)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.92)
            if let data {
                saveToLibrary(data)
                if workingSlots.indices.contains(currentSlotIndex) {
                    workingSlots[currentSlotIndex].photoData = data
                    workingSlots[currentSlotIndex].isSkipped = false
                }
            }
            isCapturing = false
            updateControls()
            if finishRequested {
                finish()
            } else {
                advanceOrFinish()
            }
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

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish()
        }
    }
}

private final class GuidedOverlayContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
