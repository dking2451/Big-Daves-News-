import SwiftUI
import UIKit
import Foundation

/// Minimal import UI: preview shared text or image, then same extract → `ReviewExtractedEventsView` as Upload flow.
struct ShareImportView: View {
    let payload: ShareHandoff.Payload

    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("backendURL") private var backendURL = BackendDefaults.defaultBackendURL

    @State private var extractedText: String = ""
    @State private var selectedImage: UIImage?
    @State private var reviewCandidates: [ExtractedEventCandidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showReviewSheet = false

    var body: some View {
        Form {
            Section {
                Text("Review before saving. Events are only added when you confirm on the next screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch payload {
            case .text(let text):
                Section("Shared text") {
                    Text(text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .image:
                Section("Shared image") {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView(
                            "Image unavailable",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text("Try sharing the image again.")
                        )
                    }
                }
                if !extractedText.isEmpty {
                    Section("Text from photo") {
                        Text(extractedText)
                            .font(.footnote.monospaced())
                            .lineLimit(10)
                    }
                }
            }

            Section {
                Button {
                    Task { await extractThenOpenReview() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Create events", systemImage: "sparkles")
                    }
                }
                .disabled(isLoading || !canExtract)

                Button {
                    saveForLater()
                } label: {
                    Label("Save for later", systemImage: "tray.and.arrow.down")
                }
                .disabled(isLoading)
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .accessibilityLabel("Close import")
            }
        }
        .onAppear(perform: loadFromPayload)
        .sheet(isPresented: $showReviewSheet) {
            NavigationStack {
                ReviewExtractedEventsView(
                    candidates: reviewCandidates,
                    onSaveCompleted: {
                        showReviewSheet = false
                        dismiss()
                    }
                )
                .environmentObject(store)
            }
        }
    }

    private var canExtract: Bool {
        switch payload {
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return selectedImage != nil
        }
    }

    private func loadFromPayload() {
        errorMessage = nil
        switch payload {
        case .text(let text):
            extractedText = text
        case .image(let url):
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                selectedImage = image
            } else {
                errorMessage = "Could not read the shared image."
            }
        }
    }

    private func extractThenOpenReview() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let ocrOrText: String
            switch payload {
            case .text(let text):
                ocrOrText = text
            case .image:
                guard let selectedImage else {
                    errorMessage = "Image is missing."
                    return
                }
                let ocr = try await OCRService.extractText(from: selectedImage)
                extractedText = ocr
                if ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "No readable text found. Try a clearer screenshot."
                    return
                }
                ocrOrText = ocr
            }

            let client = APIClient(baseURL: backendURL)
            let hint = payload.isText ? "shared text" : "shared image"
            let candidates = try await client.extractEvents(ocrText: ocrOrText, sourceHint: hint)
            reviewCandidates = candidates
            if candidates.isEmpty {
                errorMessage = "No events found. Try again or add manually."
                return
            }
            showReviewSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveForLater() {
        errorMessage = nil
        do {
            switch payload {
            case .text(let text):
                _ = try PendingImportQueue.enqueueText(text)
            case .image(let url):
                let data = try Data(contentsOf: url)
                _ = try PendingImportQueue.enqueueImageJPEG(data)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension ShareHandoff.Payload {
    var isText: Bool {
        if case .text = self { return true }
        return false
    }
}
