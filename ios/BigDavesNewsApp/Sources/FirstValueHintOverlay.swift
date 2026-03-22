import SwiftUI

/// One-time callout above Tonight’s Pick after onboarding (saved prefs).
struct FirstValueHintOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var opacity: Double = 0
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button(action: dismissNow) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("We picked this for you")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("Based on what you told us — open in your app when you’re ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                opacity = 1
            }
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        dismissNow()
                    }
                }
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to dismiss.")
    }

    private func dismissNow() {
        dismissTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }
}
