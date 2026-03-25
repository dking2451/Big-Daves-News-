import SwiftUI
import UIKit

struct PendingImportReviewSheet: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("backendURL") private var backendURL = BackendDefaults.defaultBackendURL

    let item: PendingImportItem

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reviewCandidates: [ExtractedEventCandidate] = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Extracting…")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Could not extract events",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(errorMessage)
                    )
                } else {
                    ReviewExtractedEventsView(
                        candidates: reviewCandidates,
                        onSaveCompleted: {
                            PendingImportQueue.remove(item.id)
                        }
                    )
                }
            }
        }
        .onAppear(perform: extractNow)
    }

    private func extractNow() {
        guard reviewCandidates.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            defer {
                isLoading = false
            }
            do {
                let client = APIClient(baseURL: backendURL)

                let ocrOrText: String
                switch item.kind {
                case .text:
                    guard let t = item.text else { throw PendingImportQueueError.emptyContent }
                    ocrOrText = t
                case .image:
                    guard let imageFileName = item.imageFileName else { throw PendingImportQueueError.emptyContent }
                    let imageData = try loadImageData(imageFileName: imageFileName)
                    guard let image = UIImage(data: imageData) else { throw PendingImportQueueError.emptyContent }
                    let ocr = try await OCRService.extractText(from: image)
                    guard !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw PendingImportQueueError.emptyContent
                    }
                    ocrOrText = ocr
                }

                let hint = item.kind == .text ? "pending text" : "pending image"
                reviewCandidates = try await client.extractEvents(ocrText: ocrOrText, sourceHint: hint)
                if reviewCandidates.isEmpty {
                    errorMessage = "No events found in this pending import."
                } else {
                    // Ensure the user sees the review UI (not empty list).
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadImageData(imageFileName: String) throws -> Data {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PendingImportQueueError.appSupportUnavailable
        }
        let url = base
            .appendingPathComponent("pending_import_images", isDirectory: true)
            .appendingPathComponent(imageFileName)
        return try Data(contentsOf: url)
    }
}

