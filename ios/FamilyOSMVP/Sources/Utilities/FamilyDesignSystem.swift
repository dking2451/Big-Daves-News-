import SwiftUI
import UIKit

// MARK: - Layout (rails and rhythm; mirrors Big Daves patterns, Family-specific)

enum FamilyLayout {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var isLargePad: Bool {
        guard isPad else { return false }
        let maxSide = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return maxSide >= 1366
    }

    static func useRegularWidthTabletLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        guard isPad else { return false }
        return horizontalSizeClass == .regular
    }

    static var horizontalPadding: CGFloat {
        if isLargePad { return 34 }
        return isPad ? 24 : 16
    }

    static var contentMaxWidth: CGFloat {
        if isLargePad { return 1220 }
        return isPad ? 1100 : 760
    }

    static var cardCornerRadius: CGFloat { 18 }

    static var cardInnerCornerRadius: CGFloat { 14 }

    static var headerPadding: CGFloat {
        if isLargePad { return 20 }
        return isPad ? 18 : 12
    }

    static var sectionSpacing: CGFloat {
        if isLargePad { return 32 }
        return isPad ? 28 : 24
    }

    /// Primary elevated cards (Next Up, summary blocks).
    static var cardContentPadding: CGFloat {
        if isLargePad { return 20 }
        return isPad ? 19 : 18
    }

    /// Compact rows (e.g. home timeline).
    static var compactRowPadding: CGFloat { 12 }
}

// MARK: - Theme (calm Family identity: indigo + blue)

enum FamilyTheme {
    static let accentIndigo = Color(hex: "4F46E5")
    static let accentBlue = Color(hex: "3B82F6")

    /// Tab bar, key accents, prominent controls.
    static var accent: Color { accentIndigo }

    static let accentGradient = LinearGradient(
        colors: [accentIndigo.opacity(0.92), accentBlue.opacity(0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func cardShadowColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.10)
    }

    static func cardBorderColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}

// MARK: - Elevated surface

struct FamilyElevatedCard<Content: View>: View {
    let contentPadding: CGFloat
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(contentPadding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FamilyLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FamilyLayout.cardCornerRadius, style: .continuous)
                    .stroke(FamilyTheme.cardBorderColor(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: FamilyTheme.cardShadowColor(for: colorScheme), radius: 8, x: 0, y: 4)
    }
}

/// Same elevation without default padding (e.g. disclosure groups that manage their own insets).
struct FamilyElevatedCardChrome<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FamilyLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FamilyLayout.cardCornerRadius, style: .continuous)
                    .stroke(FamilyTheme.cardBorderColor(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: FamilyTheme.cardShadowColor(for: colorScheme), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Section copy

struct FamilySectionHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Inline empty / error (import flows)

struct FamilyInlineNotice: View {
    enum Kind {
        case error
        case info
    }

    let kind: Kind
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(kind == .error ? Color.orange : FamilyTheme.accent)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FamilyLayout.cardInnerCornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind == .error ? "Error: \(message)" : message)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
