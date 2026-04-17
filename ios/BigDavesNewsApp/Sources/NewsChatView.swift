import SwiftUI

// MARK: - View Model

@MainActor
final class NewsChatViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case answered(String, isFallback: Bool)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var inputText: String = ""

    private let suggestedQuestions = [
        "What's the biggest story today?",
        "Any updates on the economy?",
        "What's happening in sports?",
        "Any major world news?",
        "What's going on in politics?",
    ]

    var suggestions: [String] { suggestedQuestions }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .loading
        do {
            let result = try await APIClient.shared.talkToNews(question: trimmed)
            state = .answered(result.answer, isFallback: result.mode == "fallback")
        } catch {
            state = .error("Couldn't reach the news assistant. Check your connection and try again.")
        }
    }

    func reset() {
        state = .idle
        inputText = ""
    }
}

// MARK: - View

struct NewsChatView: View {
    @StateObject private var vm = NewsChatViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header description
                    BrandCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ask anything about today's headlines.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.primaryText)
                            Text("Answers are grounded in today's fact-checked stories.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.subtitle)
                        }
                    }

                    // Input field
                    BrandCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                TextField("Ask about today's news…", text: $vm.inputText, axis: .vertical)
                                    .lineLimit(1...4)
                                    .font(.body)
                                    .focused($fieldFocused)
                                    .submitLabel(.send)
                                    .onSubmit {
                                        Task { await vm.ask(vm.inputText) }
                                    }

                                Button {
                                    Task { await vm.ask(vm.inputText) }
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(
                                            vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                ? AppTheme.primary.opacity(0.3)
                                                : AppTheme.primary
                                        )
                                }
                                .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .buttonStyle(.plain)
                                .accessibilityLabel("Send question")
                            }
                        }
                    }

                    // Suggestions (shown when idle)
                    if case .idle = vm.state {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Try asking…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.subtitle)
                                .padding(.horizontal, 2)

                            ForEach(vm.suggestions, id: \.self) { suggestion in
                                Button {
                                    vm.inputText = suggestion
                                    Task { await vm.ask(suggestion) }
                                } label: {
                                    HStack {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.primary)
                                        Text(suggestion)
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.primaryText)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.subtitle)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(AppTheme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius - 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Loading state
                    if case .loading = vm.state {
                        BrandCard {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(AppTheme.primary)
                                Text("Reading today's stories…")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.subtitle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Answer state
                    if case .answered(let answer, let isFallback) = vm.state {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Image(systemName: isFallback ? "newspaper" : "sparkles")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.primary)
                                    Text(isFallback ? "Relevant Headlines" : "News Assistant")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.primary)
                                    Spacer()
                                    Button {
                                        vm.reset()
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.subtitle)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Ask another question")
                                }

                                if isFallback {
                                    Text("The assistant is warming up. Here are the most relevant headlines:")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.subtitle)
                                }

                                Text(answer)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // Ask another
                        Button {
                            vm.reset()
                            fieldFocused = true
                        } label: {
                            Label("Ask another question", systemImage: "bubble.left")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppTheme.primary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius - 4))
                        }
                        .buttonStyle(.plain)
                    }

                    // Error state
                    if case .error(let message) = vm.state {
                        AppContentStateCard(
                            kind: .error,
                            systemImage: "exclamationmark.bubble",
                            title: "Couldn't get an answer",
                            message: message,
                            retryTitle: "Try again",
                            onRetry: { Task { await vm.ask(vm.inputText) } },
                            isRetryDisabled: false,
                            compact: true,
                            embedInBrandCard: true
                        )
                    }
                }
                .padding(.horizontal, DeviceLayout.horizontalPadding)
                .padding(.vertical, 16)
            }
            .navigationTitle("Ask the News")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { fieldFocused = true }
    }
}
