import SwiftUI

// MARK: - ScrollViewReader proxy (for league jump inside onboarding scroll)

private enum OnboardingScrollProxyKey: EnvironmentKey {
    static let defaultValue: ScrollViewProxy? = nil
}

extension EnvironmentValues {
    var onboardingScrollProxy: ScrollViewProxy? {
        get { self[OnboardingScrollProxyKey.self] }
        set { self[OnboardingScrollProxyKey.self] = newValue }
    }
}

// MARK: - Preference chip (reusable, accessible)

/// Selectable chip with clear selected / unselected states and light selection animation.
struct PreferenceChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let minChipHeight: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
                .frame(minHeight: minChipHeight)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.clear
                            : Color(.separator).opacity(colorScheme == .dark ? 0.45 : 0.35),
                        lineWidth: 1
                    )
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear, radius: isSelected ? 6 : 0, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Selected. Double tap to deselect." : "Double tap to select.")
    }
}

// MARK: - Screen layout (title, subtitle, scrollable content, footer CTAs)

struct OnboardingScreenLayout<Content: View>: View {
    let title: String
    var subtitle: String?
    var showsProgress: Bool = true
    var currentStep: Int
    var totalSteps: Int
    var primaryTitle: String
    var secondaryTitle: String?
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .accessibilityAddTraits(.isHeader)

                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(3)
                            }
                        }
                        .padding(.bottom, 14)

                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .environment(\.onboardingScrollProxy, proxy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)

                if let secondaryTitle, let onSecondary {
                    Button(action: onSecondary) {
                        Text(secondaryTitle)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background {
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Progress bar (segmented dots)

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accentColor : Color(.separator).opacity(0.55))
                    .frame(height: 4)
                    .frame(maxWidth: index == current ? 28 : 12)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}
