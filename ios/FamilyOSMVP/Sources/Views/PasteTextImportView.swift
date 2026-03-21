import SwiftUI
import UIKit

/// Paste schedule text from the clipboard or keyboard, extract via backend, then review before save.
struct PasteTextImportView: View {
    private static let localSimulatorURL = "http://127.0.0.1:8000"

    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("backendURL") private var backendURL = PasteTextImportView.localSimulatorURL

    @State private var pastedText = ""
    @State private var reviewCandidates: [ExtractedEventCandidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var clipboardHint: String?
    @State private var showReviewSheet = false
    @State private var didAutoRunExtraction = false

    private let autoRunExtractionOnAppear: Bool

    init(initialText: String = "", autoRunExtractionOnAppear: Bool = false) {
        _pastedText = State(initialValue: initialText)
        self.autoRunExtractionOnAppear = autoRunExtractionOnAppear
    }

    private var trimmedForExtract: String {
        pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canExtract: Bool {
        !trimmedForExtract.isEmpty
    }

    var body: some View {
        Form {
            Section {
                Text("Nothing is saved until you review and confirm on the next screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if pastedText.isEmpty {
                        Text(Self.placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $pastedText)
                        .font(.body)
                        .frame(minHeight: 220)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Your text")
            }

            Section {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                if let clipboardHint {
                    Text(clipboardHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await runExtraction() }
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Extracting…")
                        }
                    } else {
                        Text("Extract Events")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(!canExtract || isLoading)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Paste Text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityLabel("Cancel paste import")
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            NavigationStack {
                ReviewExtractedEventsView(candidates: reviewCandidates)
                    .environmentObject(store)
            }
        }
        .task {
            guard autoRunExtractionOnAppear, !didAutoRunExtraction else { return }
            let text = trimmedForExtract
            guard !text.isEmpty else { return }
            didAutoRunExtraction = true
            await runExtraction()
        }
    }

    private static let placeholder = """
Paste a message, email, or schedule text here…
Example: Soccer practice Thursday at 5pm at Blue Field.
"""

    private func pasteFromClipboard() {
        clipboardHint = nil
        guard let s = UIPasteboard.general.string else {
            clipboardHint = "Clipboard has no text. Copy something first, then try again."
            return
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clipboardHint = "Clipboard is empty. Copy text first, then try again."
            return
        }
        pastedText = s
    }

    private func runExtraction() async {
        errorMessage = nil
        let text = trimmedForExtract
        guard !text.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let client = APIClient(baseURL: backendURL)
            let candidates = try await client.extractEvents(ocrText: text, sourceHint: "pasted text")
            reviewCandidates = candidates
            if candidates.isEmpty {
                errorMessage = "No events found. You can edit the text and try again, or add events manually."
                return
            }
            showReviewSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
