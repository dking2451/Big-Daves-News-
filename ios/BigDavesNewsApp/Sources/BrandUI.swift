import SwiftUI
import UIKit

enum AppTheme {
    static let primary = Color(red: 0.04, green: 0.28, blue: 0.72)
    static let accent = Color(red: 0.01, green: 0.60, blue: 0.63)
    static let pageBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let cardBorder = Color(.separator).opacity(0.14)
    static let subtitle = Color.secondary
}

enum DeviceLayout {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var isLargePad: Bool {
        guard isPad else { return false }
        let maxSide = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return maxSide >= 1366
    }
    static var horizontalPadding: CGFloat {
        if isLargePad { return 34 }
        return isPad ? 28 : 16
    }
    static var contentMaxWidth: CGFloat {
        if isLargePad { return 1220 }
        return isPad ? 1100 : 760
    }
    static var cardCornerRadius: CGFloat {
        if isLargePad { return 20 }
        return isPad ? 18 : 14
    }
    static var headerPadding: CGFloat {
        if isLargePad { return 20 }
        return isPad ? 18 : 12
    }
    static var sectionSpacing: CGFloat {
        if isLargePad { return 16 }
        return isPad ? 14 : 12
    }
}

enum AppHaptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func lightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

struct BrandCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DeviceLayout.isPad ? 18 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: bevelStrokeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: primaryShadowColor, radius: 14, x: 0, y: 6)
            .shadow(color: secondaryShadowColor, radius: 3, x: 0, y: 1)
    }

    private var bevelStrokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.black.opacity(0.24)]
        }
        return [Color.white.opacity(0.75), Color.black.opacity(0.12)]
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.34) : Color.black.opacity(0.10)
    }

    private var secondaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.16) : Color.black.opacity(0.05)
    }
}

struct AppSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.subtitle)
        }
    }
}

struct AppBrandedHeader: View {
    let sectionTitle: String
    let sectionSubtitle: String
    private var brandBadgeFont: Font {
        if DeviceLayout.isLargePad { return .body.weight(.black) }
        if DeviceLayout.isPad { return .subheadline.weight(.black) }
        return .caption.weight(.black)
    }
    private var brandNameFont: Font {
        if DeviceLayout.isLargePad { return .title3.weight(.semibold) }
        if DeviceLayout.isPad { return .headline.weight(.semibold) }
        return .subheadline.weight(.semibold)
    }
    private var sectionTitleFont: Font {
        if DeviceLayout.isLargePad { return .largeTitle.weight(.bold) }
        if DeviceLayout.isPad { return .title.weight(.bold) }
        return .title2.weight(.bold)
    }
    private var subtitleFont: Font {
        if DeviceLayout.isLargePad { return .body }
        if DeviceLayout.isPad { return .subheadline }
        return .footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DeviceLayout.isLargePad ? 12 : 8) {
            HStack(spacing: 10) {
                Text("BDN")
                    .font(brandBadgeFont)
                    .padding(.horizontal, DeviceLayout.isPad ? 10 : 8)
                    .padding(.vertical, DeviceLayout.isPad ? 5 : 4)
                    .background(Color.white.opacity(0.2))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                Text("Big Daves News")
                    .font(brandNameFont)
                    .foregroundStyle(Color.white)
                if DeviceLayout.isPad {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            Text(sectionTitle)
                .font(sectionTitleFont)
                .foregroundStyle(Color.white)
            Text(sectionSubtitle)
                .font(subtitleFont)
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(DeviceLayout.isPad ? 3 : 2)
        }
        .padding(DeviceLayout.headerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.primary, AppTheme.accent, AppTheme.primary.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SkeletonLine: View {
    let width: CGFloat?
    let height: CGFloat

    init(width: CGFloat? = nil, height: CGFloat = 12) {
        self.width = width
        self.height = height
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
    }
}

struct SkeletonCard: View {
    var body: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonLine(width: 140, height: 14)
                SkeletonLine(height: 12)
                SkeletonLine(width: 220, height: 12)
                SkeletonLine(width: 110, height: 10)
            }
        }
    }
}

struct ErrorStateCard: View {
    let title: String
    let message: String
    let retryTitle: String
    let isRetryDisabled: Bool
    let onRetry: () -> Void

    init(
        title: String = "Something went wrong",
        message: String,
        retryTitle: String = "Try Again",
        isRetryDisabled: Bool = false,
        onRetry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.isRetryDisabled = isRetryDisabled
        self.onRetry = onRetry
    }

    var body: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetryDisabled)
            }
        }
    }
}
