import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    private final class DocumentFrameOverlayView: UIView {
        static let horizontalInset: CGFloat = 28
        static let verticalCenterOffset: CGFloat = -8
        static let heightMultiplier: CGFloat = 0.64

        private let frameView = UIView()
        private let instructionLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false

            frameView.translatesAutoresizingMaskIntoConstraints = false
            frameView.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
            frameView.layer.borderWidth = 2
            frameView.layer.cornerRadius = 14
            frameView.backgroundColor = UIColor.clear
            frameView.layer.shadowColor = UIColor.black.cgColor
            frameView.layer.shadowOpacity = 0.35
            frameView.layer.shadowRadius = 8
            frameView.layer.shadowOffset = CGSize(width: 0, height: 3)
            addSubview(frameView)

            instructionLabel.translatesAutoresizingMaskIntoConstraints = false
            instructionLabel.text = "Fit the schedule inside this frame (move closer if needed)"
            instructionLabel.textColor = .white
            instructionLabel.font = UIFont.preferredFont(forTextStyle: .headline)
            instructionLabel.numberOfLines = 2
            instructionLabel.textAlignment = .center
            instructionLabel.adjustsFontForContentSizeCategory = true
            instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.38)
            instructionLabel.layer.cornerRadius = 10
            instructionLabel.layer.masksToBounds = true
            instructionLabel.accessibilityLabel = "Fit the schedule inside this frame. Move the phone closer if the text is too small."
            addSubview(instructionLabel)

            NSLayoutConstraint.activate([
                frameView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
                frameView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
                frameView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: Self.verticalCenterOffset),
                frameView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: Self.heightMultiplier),

                instructionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
                instructionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
                instructionLabel.bottomAnchor.constraint(equalTo: frameView.topAnchor, constant: -14),
                instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            ])
        }

        static func normalizedCaptureRect(in bounds: CGRect) -> CGRect {
            guard bounds.width > 1, bounds.height > 1 else {
                return CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            let width = bounds.width - (horizontalInset * 2)
            let height = bounds.height * heightMultiplier
            let x = horizontalInset
            let y = ((bounds.height - height) / 2) + verticalCenterOffset
            let rect = CGRect(x: x, y: y, width: width, height: height).intersection(bounds)
            return CGRect(
                x: rect.minX / bounds.width,
                y: rect.minY / bounds.height,
                width: rect.width / bounds.width,
                height: rect.height / bounds.height
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    // We intentionally do **not** use `cameraViewTransform` pinch zoom: it applies to the live preview
    // layer only. After the shutter, the Retake/Use Photo screen shows the still in a different layer,
    // so pinches still mutate `cameraViewTransform` while the overlay stays separate—bad UX. True
    // preview zoom needs `AVCaptureDevice`/`AVCaptureSession` (custom camera) or post-capture crop.

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                if parent.sourceType == .camera {
                    if parent.deferCameraGuideCrop {
                        parent.onImagePicked(image)
                    } else {
                        let overlayBounds = picker.view.bounds
                        let normalizedRect = DocumentFrameOverlayView.normalizedCaptureRect(in: overlayBounds)
                        parent.onImagePicked(parent.cropToNormalizedRect(image: image, normalizedRect: normalizedRect))
                    }
                } else {
                    parent.onImagePicked(image)
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }

    let sourceType: UIImagePickerController.SourceType
    /// When true, the camera returns the **full** photo; the caller can show crop options (same as Photos flow).
    var deferCameraGuideCrop: Bool = false
    let onImagePicked: (UIImage) -> Void
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        if sourceType == .camera {
            picker.cameraOverlayView = DocumentFrameOverlayView(frame: picker.view.bounds)
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        if uiViewController.sourceType == .camera, let overlay = uiViewController.cameraOverlayView {
            overlay.frame = uiViewController.view.bounds
        }
    }

    private func cropToNormalizedRect(image: UIImage, normalizedRect: CGRect) -> UIImage {
        let normalized = image.normalizedOrientationImage()
        guard let cgImage = normalized.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let rect = CGRect(
            x: max(0, min(1, normalizedRect.minX)) * width,
            y: max(0, min(1, normalizedRect.minY)) * height,
            width: max(0.1, min(1, normalizedRect.width)) * width,
            height: max(0.1, min(1, normalizedRect.height)) * height
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cropped = cgImage.cropping(to: rect.integral), rect.width > 1, rect.height > 1 else {
            return normalized
        }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }
}

private extension UIImage {
    func normalizedOrientationImage() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
