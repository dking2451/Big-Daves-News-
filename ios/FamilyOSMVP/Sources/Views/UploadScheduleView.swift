import PhotosUI
import SwiftUI
import UIKit

struct UploadScheduleView: View {
    @AppStorage("backendURL") private var backendURL = BackendDefaults.defaultBackendURL

    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    /// Photo from camera or library before user chooses crop vs full image.
    @State private var pendingCropImage: UIImage?
    @State private var pendingCropFromCamera = false
    @State private var showCamera = false
    @State private var showImageCropDialog = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var extractedTextPreview = ""
    @State private var reviewCandidates: [ExtractedEventCandidate] = []

    var body: some View {
        List {
            #if !targetEnvironment(simulator)
            if BackendDefaults.isLocalhostBackendURL(backendURL) {
                Section {
                    Text(
                        "Backend URL points to this device (localhost). On a real iPhone that cannot reach your Mac. Open Settings → Backend → Use Render, or enter your Mac’s LAN IP with the server running."
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
            #endif

            Section("Upload") {
                PhotosPicker(selection: $selectedPickerItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        errorMessage = "Camera is not available on this device."
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Select a screenshot or take a photo to start extraction.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !extractedTextPreview.isEmpty {
                Section("OCR Preview") {
                    Text(extractedTextPreview)
                        .font(.footnote.monospaced())
                        .lineLimit(8)
                }
            }

            Section {
                Button {
                    Task { await runExtraction() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Extract Candidate Events", systemImage: "sparkles")
                    }
                }
                .disabled(selectedImage == nil || isLoading)
            }

            if let errorMessage {
                Section {
                    FamilyInlineNotice(kind: .error, message: errorMessage)
                }
            }

            if !reviewCandidates.isEmpty {
                Section("Latest Result") {
                    NavigationLink {
                        ReviewExtractedEventsView(candidates: reviewCandidates)
                    } label: {
                        Label("Review \(reviewCandidates.count) candidate events", systemImage: "checklist")
                    }
                }
            }
        }
        .navigationTitle("Upload Schedule")
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                sourceType: .camera,
                deferCameraGuideCrop: true,
                onImagePicked: { image in
                    pendingCropImage = image
                    pendingCropFromCamera = true
                    showImageCropDialog = true
                },
                dismiss: { showCamera = false }
            )
        }
        .onChange(of: selectedPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pendingCropImage = image
                    pendingCropFromCamera = false
                    showImageCropDialog = true
                }
            }
        }
        .confirmationDialog(
            pendingCropFromCamera ? "Prepare photo for OCR" : "Prepare image for OCR",
            isPresented: $showImageCropDialog,
            presenting: pendingCropImage
        ) { image in
            Button("Crop to frame (recommended)") {
                applyPendingImage(image, useGuideCrop: true)
            }
            Button("Use full image") {
                applyPendingImage(image, useGuideCrop: false)
            }
            if pendingCropFromCamera {
                Button("Retake") {
                    pendingCropImage = nil
                    pendingCropFromCamera = false
                    showImageCropDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showCamera = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCropImage = nil
                pendingCropFromCamera = false
            }
        } message: { _ in
            if pendingCropFromCamera {
                Text("Choose how much of the photo to send to OCR. Retake if the flyer isn’t in frame.")
            } else {
                Text("Cropping helps OCR ignore UI chrome and background outside the flyer.")
            }
        }
    }

    private func applyPendingImage(_ image: UIImage, useGuideCrop: Bool) {
        selectedImage = useGuideCrop ? cropToGuideFrame(image) : image
        pendingCropImage = nil
        pendingCropFromCamera = false
        showImageCropDialog = false
    }

    private func runExtraction() async {
        guard let selectedImage else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let ocrText = try await OCRService.extractText(from: selectedImage)
            extractedTextPreview = ocrText
            if ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "No readable text found in this image. Try a clearer screenshot."
                reviewCandidates = []
                return
            }

            let client = APIClient(baseURL: backendURL)
            let candidates = try await client.extractEvents(ocrText: ocrText, sourceHint: "schedule image")
            reviewCandidates = candidates
            if candidates.isEmpty {
                errorMessage = "No events were found. You can try another image or add events manually."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Matches the camera guide box crop used during capture.
    private func cropToGuideFrame(_ image: UIImage) -> UIImage {
        let normalized = image.normalizedOrientationImage()
        guard let cgImage = normalized.cgImage else { return image }

        let screen = UIScreen.main.bounds
        let insetRatio = 28 / max(screen.width, 1)
        let centerOffsetRatio = -8 / max(screen.height, 1)
        let heightRatio: CGFloat = 0.64
        let widthRatio = max(0.1, 1 - (insetRatio * 2))
        let yRatio = ((1 - heightRatio) / 2) + centerOffsetRatio
        let frameRect = CGRect(
            x: normalized.size.width * insetRatio,
            y: normalized.size.height * yRatio,
            width: normalized.size.width * widthRatio,
            height: normalized.size.height * heightRatio
        ).intersection(CGRect(origin: .zero, size: normalized.size))

        guard frameRect.width > 1, frameRect.height > 1 else { return normalized }
        let cropRect = CGRect(
            x: frameRect.minX * normalized.scale,
            y: frameRect.minY * normalized.scale,
            width: frameRect.width * normalized.scale,
            height: frameRect.height * normalized.scale
        ).integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return normalized }
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
