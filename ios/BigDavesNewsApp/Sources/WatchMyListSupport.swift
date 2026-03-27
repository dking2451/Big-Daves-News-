import SwiftUI

// MARK: - Navigation (Phase 1 → 2)

/// Routes pushed from the Watch tab stack. Phase 2 can add hub sections without breaking `.list`.
enum WatchMyListRoute: Hashable {
    case list
}

// MARK: - Save confirmation (Phase 1)

@MainActor
final class WatchMyListSaveFeedback: ObservableObject {
    static let shared = WatchMyListSaveFeedback()

    struct Toast: Equatable {
        var message: String
        var actionTitle: String
    }

    @Published private(set) var toast: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Call after a **successful** save (`saved == true`).
    func presentAddedToList() {
        dismissTask?.cancel()
        toast = Toast(message: "Added to your list", actionTitle: "View My List")
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard let self, self.toast != nil else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    self.toast = nil
                }
            }
        }
    }

    func dismissToast() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            toast = nil
        }
    }

    func viewMyListTapped() {
        dismissToast()
        AppNavigationState.shared.openWatchMyList()
    }
}

/// Compact bottom banner: message + text button (premium, non-blocking).
struct WatchSaveConfirmationBanner: View {
    @ObservedObject private var feedback = WatchMyListSaveFeedback.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let toast = feedback.toast {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.green)
                            .accessibilityHidden(true)

                        Text(toast.message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)

                        Button(toast.actionTitle) {
                            AppHaptics.selection()
                            feedback.viewMyListTapped()
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(AppTheme.primary)
                        .controlSize(dynamicTypeSize >= .accessibility2 ? .large : .regular)
                        .accessibilityLabel(toast.actionTitle)
                        .accessibilityHint("Opens My List.")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, dynamicTypeSize >= .accessibility2 ? 14 : 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, y: 4)
                    .padding(.horizontal, DeviceLayout.horizontalPadding)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(toast.message). \(toast.actionTitle)")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: feedback.toast != nil)
    }
}
