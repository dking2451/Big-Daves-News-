import PhotosUI
import SwiftUI
import UIKit

struct UploadScheduleView: View {
    @AppStorage("backendURL") private var backendURL = "https://family-os-mvp-api.onrender.com"

    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var extractedTextPreview = ""
    @State private var reviewCandidates: [ExtractedEventCandidate] = []

    var body: some View {
        List {
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
                    Text(errorMessage)
                        .foregroundStyle(.red)
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
                onImagePicked: { selectedImage = $0 },
                dismiss: { showCamera = false }
            )
        }
        .onChange(of: selectedPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }

    private func runExtraction() async {
        guard let selectedImage else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let ocrText = try await OCRService.extractText(from: selectedImage)
            extractedTextPreview = ocrText

            let client = APIClient(baseURL: backendURL)
            let candidates = try await client.extractEvents(ocrText: ocrText, sourceHint: "schedule image")
            reviewCandidates = candidates
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
