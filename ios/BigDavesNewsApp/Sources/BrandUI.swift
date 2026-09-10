import SwiftUI
import UIKit

enum AppTheme {
    static let primary = Color(hex: "3B82F6")
    static let accent = Color(hex: "14B8A6")
    static let ochoAccent = Color(hex: "A855F7")
    static let pageBackground = Color("appBackground")
    static let toolbarBackground = Color("toolbarBackground")

    // MARK: Watch — dark-first canvas
    static let watchCanvasDark = Color(red: 0.06, green: 0.07, blue: 0.11)
    static let watchSecondaryAccent = Color(red: 0.45, green: 0.72, blue: 0.88)

    static func watchScreenBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? watchCanvasDark : pageBackground
    }

    static func tonightBackgroundOverlay(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.07) : Color.black.opacity(0.035)
    }
    static let cardBackground = Color("cardBackground")
    static let secondaryBackground = Color("secondaryBackground")
    static let cardBorder = Color("cardBorder")
    static let primaryText = Color("primaryText")
    static let secondaryText = Color("secondaryText")
    static let tertiaryText = Color("tertiaryText")
    static let subtitle = secondaryText
    static let liveRed = Color(hex: "EF4444")
    static let soonYellow = Color(hex: "EAB308")
    static let positiveGreen = Color(hex: "22C55E")
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "3B82F6"), Color(hex: "14B8A6")],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let streakGradient = LinearGradient(
        colors: [Color(hex: "D97706"), Color(hex: "B45309")],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: iOS 27 polish — glass system tokens
    /// 135° variant of `primaryGradient` for square fills (brand mark, toolbar primary, tab pill).
    static let primaryGradientDiagonal = LinearGradient(
        colors: [Color(hex: "3B82F6"), Color(hex: "14B8A6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static func cardTint(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 28 / 255, green: 32 / 255, blue: 44 / 255).opacity(0.55)
            : Color.white.opacity(0.78)
    }
    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color(hex: "0F172A").opacity(0.07)
    }
    static func chromeFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.70)
    }
    static func tabBarTint(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 30 / 255, green: 34 / 255, blue: 44 / 255).opacity(0.62)
            : Color.white.opacity(0.72)
    }
    static func neutralButtonFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color(hex: "0F172A").opacity(0.05)
    }
    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.42) : Color(hex: "0F172A").opacity(0.10)
    }
    static func chromeShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.10)
    }
}

enum DeviceLayout {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var isLargePad: Bool {
        guard isPad else { return false }
        let maxSide = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return maxSide >= 1366
    }

    /// Use multi-column / split layouts on full-width iPad. Returns `false` on iPhone and in compact width (Slide Over, some split views).
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
    static var cardCornerRadius: CGFloat {
        18
    }
    static var headerPadding: CGFloat {
        if isLargePad { return 20 }
        return isPad ? 18 : 12
    }
    static var sectionSpacing: CGFloat {
        if isLargePad { return 32 }
        return isPad ? 28 : 24
    }
    /// Vertical space between title and subtitle in `ScreenIntentHeader`.
    static var screenIntentTitleSubtitleSpacing: CGFloat {
        if isLargePad { return 6 }
        return isPad ? 5 : 4
    }
    /// Space below the screen-intent block before the branded hero card.
    static var screenIntentToBrandedSpacing: CGFloat {
        if isLargePad { return 12 }
        return isPad ? 10 : 8
    }
}

enum AppTypography {
    static let largeTitle = Font.system(size: 34, weight: .semibold)
    static let title1 = Font.system(size: 28, weight: .semibold)
    static let title2 = Font.system(size: 22, weight: .semibold)
    static let title3 = Font.system(size: 20, weight: .medium)
    static let body = Font.system(size: 17, weight: .regular)
    static let callout = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let footnote = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
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

/// Legacy card name — now a thin alias of the glass `BDNCard` so every existing
/// call site inherits the iOS 27 surface without a per-site rewrite.
struct BrandCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        BDNCard { content }
    }
}

struct AppSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.title2)
            Text(subtitle)
                .font(AppTypography.footnote)
                .foregroundStyle(AppTheme.subtitle)
        }
    }
}

/// Lightweight screen-intent label at the top of a tab: clarifies purpose without replacing the branded hero.
struct ScreenIntentHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder private var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: DeviceLayout.screenIntentTitleSubtitleSpacing) {
                Text(title)
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(AppTypography.callout)
                    .foregroundStyle(AppTheme.subtitle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppBrandedHeader: View {
    let sectionTitle: String
    let sectionSubtitle: String
    /// When false, only the BDN / Big Daves News row is shown (pair with `ScreenIntentHeader` above).
    var showSectionHeading: Bool = true

    init(sectionTitle: String, sectionSubtitle: String, showSectionHeading: Bool = true) {
        self.sectionTitle = sectionTitle
        self.sectionSubtitle = sectionSubtitle
        self.showSectionHeading = showSectionHeading
    }
    private var brandBadgeFont: Font {
        .subheadline.weight(.black)
    }
    private var brandNameFont: Font {
        .headline.weight(.semibold)
    }
    private var sectionTitleFont: Font {
        if DeviceLayout.isLargePad { return .largeTitle.weight(.bold) }
        if DeviceLayout.isPad { return .title.weight(.bold) }
        return AppTypography.title1
    }
    private var subtitleFont: Font {
        if DeviceLayout.isLargePad { return .body }
        if DeviceLayout.isPad { return .subheadline }
        return AppTypography.callout
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
            if showSectionHeading {
                Text(sectionTitle)
                    .font(sectionTitleFont)
                    .foregroundStyle(Color.white)
                Text(sectionSubtitle)
                    .font(subtitleFont)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(DeviceLayout.isPad ? 3 : 2)
            }
        }
        .padding(DeviceLayout.headerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.primaryGradient
        )
        .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

/// Thin brand indicator for secondary tabs — replaces the full-height `AppBrandedHeader` gradient card.
/// Shows just the BDN pill + app name as a single horizontal row with no background card.
struct AppBrandedStripe: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("BDN")
                .font(.caption2.weight(.black))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppTheme.primary.opacity(0.12))
                .foregroundStyle(AppTheme.primary)
                .clipShape(Capsule())
            Text("Big Daves News")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
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

/// Calm empty / error placeholder aligned with `BrandCard` styling (dark mode + Dynamic Type friendly).
struct AppContentStateCard: View {
    enum Kind {
        case empty
        case error
    }

    let kind: Kind
    let systemImage: String
    let title: String
    let message: String
    var retryTitle: String? = "Try again"
    var onRetry: (() -> Void)?
    var isRetryDisabled: Bool = false
    /// Tighter layout for inline use (e.g. a single list section).
    var compact: Bool = false
    /// Set false when already inside a `BrandCard` or list section to avoid double borders.
    var embedInBrandCard: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let core = VStack(alignment: .center, spacing: compact ? 8 : 12) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 28 : 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconForeground)
                .accessibilityHidden(true)

            Text(title)
                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(compact ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .disabled(isRetryDisabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 6 : 2)

        Group {
            if embedInBrandCard {
                BrandCard { core }
            } else {
                core
                    .padding(compact ? 10 : 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(colorScheme == .dark ? 0.35 : 0.65))
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var iconForeground: Color {
        switch kind {
        case .empty:
            return AppTheme.primary.opacity(colorScheme == .dark ? 0.95 : 0.88)
        case .error:
            return Color.orange
        }
    }

    private var accessibilitySummary: String {
        var s = "\(title). \(message)"
        if let retryTitle, onRetry != nil {
            s += ". \(retryTitle)"
        }
        return s
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
        AppContentStateCard(
            kind: .error,
            systemImage: "exclamationmark.triangle.fill",
            title: title,
            message: message,
            retryTitle: retryTitle,
            onRetry: onRetry,
            isRetryDisabled: isRetryDisabled,
            compact: false,
            embedInBrandCard: true
        )
    }
}

struct PrimaryGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // LinearGradient conforms to both View and ShapeStyle, and each declares its own
            // opacity(_:), so a bare .opacity() here is ambiguous. AnyShapeStyle pins it to
            // the ShapeStyle overload, keeping the original fill behaviour.
            .background(AnyShapeStyle(AppTheme.primaryGradient.opacity(configuration.isPressed ? 0.88 : 1)))
            .clipShape(Capsule())
            .shadow(color: AppTheme.primary.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? Color(hex: "CBD5E1") : Color(hex: "334155"))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                (colorScheme == .dark ? Color(hex: "334155") : Color(hex: "F1F5F9"))
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - App-wide simple toast

/// Lightweight ephemeral toast for save/action confirmations.
/// Usage: attach `.appToast(message:isPresented:)` to any view.
@MainActor
final class AppToastState: ObservableObject {
    @Published var message: String = ""
    @Published var isVisible: Bool = false
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: Double = 2.2) {
        dismissTask?.cancel()
        self.message = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isVisible = true
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    self?.isVisible = false
                }
            }
        }
    }
}

struct AppToastBanner: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 10, y: 3)
        .padding(.horizontal, DeviceLayout.horizontalPadding)
    }
}

extension View {
    func appToastOverlay(toast: AppToastState) -> some View {
        self.overlay(alignment: .bottom) {
            Group {
                if toast.isVisible {
                    AppToastBanner(message: toast.message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 6)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: toast.isVisible)
        }
    }
}

enum AppToolbarIconRole {
    case location
    case refresh
    case neutral
}

struct AppToolbarIcon: View {
    let systemName: String
    var role: AppToolbarIconRole = .neutral

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .semibold))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .foregroundStyle(foregroundColor)
    }

    private var foregroundColor: Color {
        switch role {
        case .location:
            return AppTheme.accent
        case .refresh:
            return AppTheme.primary
        case .neutral:
            return AppTheme.secondaryText
        }
    }
}

// MARK: - Content source chips (Headlines, Sports)

/// User-facing labels shown in chips and detail; map from backend enums / screen context.
enum ContentSourceLabel: String, CaseIterable {
    case curated = "Curated"
    case local = "Local"
    case espnLive = "ESPN Live"
    case espnExtended = "ESPN alt slate"
    case stadiumListing = "Stadium Listing"
    case curatedListing = "Curated Listing"
}

/// Maps API / pipeline values to user-facing `ContentSourceLabel`.
enum ContentSourceMapping {
    static func headlinesFactsChip() -> ContentSourceLabel {
        .curated
    }

    static func headlinesLocalChip() -> ContentSourceLabel {
        .local
    }

    /// Chip for sports list rows; returns `nil` when we shouldn’t imply a known pipeline.
    static func sportsCardLabel(for sourceType: String?) -> ContentSourceLabel? {
        let raw = (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "live_feed":
            return .espnLive
        case "espn_extended":
            return .espnExtended
        case "curated":
            return .curatedListing
        case "stadium_curated":
            return .stadiumListing
        case "showcase":
            return .curatedListing
        case "":
            return .espnLive
        default:
            return nil
        }
    }

    static func sportsDetailTitle(for sourceType: String?) -> String {
        let raw = (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "live_feed", "":
            return "ESPN live data"
        case "espn_extended":
            return "ESPN extended slate"
        case "curated", "showcase":
            return "Curated listing"
        case "stadium_curated":
            return "Stadium listing"
        default:
            return "Other"
        }
    }

    static func sportsDetailFootnote(for sourceType: String?) -> String {
        let raw = (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "live_feed", "":
            return "Schedules, scores, and broadcast info come from ESPN’s public feed. Availability on your provider is estimated separately."
        case "espn_extended":
            return "This event comes from ESPN’s extended scoreboard (alt / international / college feeds)."
        case "curated", "stadium_curated", "showcase":
            return "Times and titles are hand-curated and may differ from live TV or streaming availability in your area."
        default:
            if raw.isEmpty {
                return sportsDetailFootnote(for: "live_feed")
            }
            return "Source type “\(sourceType ?? "")” — see team and network details below."
        }
    }
}

// MARK: - iOS 27 polish — shared primitives

/// Glass surface used by cards, chrome and the tab bar. Falls back to an opaque
/// fill when the viewer has Reduce Transparency enabled.
private struct BDNGlass: ViewModifier {
    let cornerRadius: CGFloat
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if reduceTransparency {
                shape.fill(AppTheme.cardBackground)
            } else {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint) }
                }
            }
        }
    }
}

extension View {
    func bdnGlass(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(BDNGlass(cornerRadius: cornerRadius, tint: tint))
    }
}

/// Press feedback shared by toolbar / tab controls: scale to 0.94 with a spring.
struct BDNPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The one card surface for the whole app — 24pt continuous radius over `.ultraThinMaterial`.
struct BDNCard<Content: View>: View {
    /// List-style cards use tighter vertical padding so rows own their own 13pt insets.
    let listStyle: Bool
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(listStyle: Bool = false, @ViewBuilder content: () -> Content) {
        self.listStyle = listStyle
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, listStyle ? 6 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bdnGlass(cornerRadius: 24, tint: AppTheme.cardTint(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.hairline(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(
                color: AppTheme.cardShadow(for: colorScheme),
                radius: colorScheme == .dark ? 20 : 18,
                x: 0,
                y: colorScheme == .dark ? 8 : 7
            )
    }
}

/// Section title (+ optional subtitle), always drawn OUTSIDE the card.
struct BDNSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.24)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A single 36×36 circular glyph in the toolbar capsule. The primary (middle)
/// action carries the brand gradient with a white glyph.
struct BDNToolbarGlyph: View {
    let systemName: String
    var filled: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if filled {
                Circle().fill(AppTheme.primaryGradientDiagonal)
            }
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(glyphColor)
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
    }

    private var glyphColor: Color {
        if filled { return .white }
        return colorScheme == .dark ? AppTheme.primaryText : Color(hex: "334155")
    }
}

struct BDNToolbarAction {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
}

/// Floating capsule of exactly three 36×36 actions; the middle one is the screen's
/// primary verb and always carries the gradient. The trailing slot is supplied by
/// the caller (normally the overflow menu).
struct BDNToolbar<Trailing: View>: View {
    let leading: BDNToolbarAction
    let primary: BDNToolbarAction
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            Button(action: leading.action) {
                BDNToolbarGlyph(systemName: leading.systemName)
            }
            .buttonStyle(BDNPressButtonStyle())
            .accessibilityLabel(leading.accessibilityLabel)

            Button(action: primary.action) {
                BDNToolbarGlyph(systemName: primary.systemName, filled: true)
            }
            .buttonStyle(BDNPressButtonStyle())
            .accessibilityLabel(primary.accessibilityLabel)

            trailing()
        }
        .padding(.horizontal, 4)
        .frame(height: 40)
        .bdnGlass(cornerRadius: 20, tint: AppTheme.chromeFill(for: colorScheme))
        .overlay(
            Capsule().stroke(AppTheme.hairline(for: colorScheme), lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .shadow(color: AppTheme.chromeShadow(for: colorScheme), radius: 10, x: 0, y: 4)
    }
}

/// A selectable scoping pill; optionally carries a leading status dot (Sports).
struct BDNChip: Identifiable, Equatable {
    let id: String
    let label: String
    var dotColor: Color?

    init(id: String? = nil, label: String, dotColor: Color? = nil) {
        self.id = id ?? label
        self.label = label
        self.dotColor = dotColor
    }

    static func == (lhs: BDNChip, rhs: BDNChip) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label
    }
}

/// One scoping-control vocabulary for the whole app.
struct BDNChipRail: View {
    let chips: [BDNChip]
    @Binding var selection: String
    var onSelect: ((String) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let selected = chip.id == selection
                    Button {
                        AppHaptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selection = chip.id
                        }
                        onSelect?(chip.id)
                    } label: {
                        HStack(spacing: 6) {
                            if let dot = chip.dotColor {
                                Circle().fill(dot).frame(width: 7, height: 7)
                            }
                            Text(chip.label)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(labelColor(selected))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(fillColor(selected))
                        )
                        .overlay(
                            selected
                                ? nil
                                : Capsule().stroke(AppTheme.hairline(for: colorScheme), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func fillColor(_ selected: Bool) -> Color {
        if selected {
            return colorScheme == .dark ? Color.white : AppTheme.primaryText
        }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.8)
    }

    private func labelColor(_ selected: Bool) -> Color {
        if selected {
            return colorScheme == .dark ? Color.black : Color.white
        }
        return colorScheme == .dark ? Color(hex: "CBD5E1") : Color(hex: "334155")
    }
}

/// The screen header: brand mark row, large title, subtitle, and a trailing toolbar.
struct BDNScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.primaryGradientDiagonal)
                    .frame(width: 18, height: 18)
                Text("BIG DAVES NEWS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(
                        colorScheme == .dark
                            ? AppTheme.secondaryText.opacity(0.85)
                            : Color(hex: "64748B")
                    )
            }
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.82)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        // At accessibility sizes the toolbar stacks below the title rather than beside it.
        if dynamicTypeSize >= .accessibility1 {
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                trailing().fixedSize()
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                titleBlock
                trailing().fixedSize()
            }
        }
    }
}

/// Floating tab bar — a capsule with a gradient selection pill.
/// Built as a reusable primitive; wired into `RootTabView` in a later step.
struct BDNTabBar: View {
    struct Item: Identifiable {
        let tab: AppTab
        let systemName: String
        let label: String
        var showsLiveDot: Bool = false
        var id: AppTab { tab }
    }

    let items: [Item]
    @Binding var selection: AppTab
    @Namespace private var pillNamespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = item.tab == selection
                Button {
                    AppHaptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selection = item.tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            Image(systemName: item.systemName)
                                .font(.system(size: 21, weight: selected ? .semibold : .regular))
                            if item.showsLiveDot {
                                Circle()
                                    .fill(AppTheme.liveRed)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle().stroke(tabBarStrokeFill, lineWidth: 3)
                                    )
                                    .offset(x: 8, y: -2)
                            }
                        }
                        Text(item.label)
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Color.white : unselectedColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(AppTheme.primaryGradientDiagonal)
                                .matchedGeometryEffect(id: "bdnTabPill", in: pillNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .bdnGlass(cornerRadius: 32, tint: AppTheme.tabBarTint(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AppTheme.hairline(for: colorScheme), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.5) : Color(hex: "0F172A").opacity(0.16),
            radius: 18,
            x: 0,
            y: 6
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
    }

    private var unselectedColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color(hex: "64748B")
    }

    private var tabBarStrokeFill: Color {
        colorScheme == .dark
            ? Color(red: 30 / 255, green: 34 / 255, blue: 44 / 255)
            : Color.white
    }
}

// MARK: - Previews

#Preview("BDN primitives") {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            BDNScreenHeader(title: "Brief", subtitle: "Wednesday, 10 September") {
                BDNToolbar(
                    leading: .init(systemName: "bookmark.fill", accessibilityLabel: "Saved", action: {}),
                    primary: .init(systemName: "arrow.triangle.2.circlepath", accessibilityLabel: "Refresh", action: {})
                ) {
                    BDNToolbarGlyph(systemName: "ellipsis.circle")
                }
            }
            BDNChipRail(
                chips: [
                    BDNChip(label: "All"),
                    BDNChip(label: "Local"),
                    BDNChip(label: "World"),
                    BDNChip(label: "Politics"),
                ],
                selection: .constant("All")
            )
            VStack(alignment: .leading, spacing: 12) {
                BDNSectionHeader(title: "Your morning brief", subtitle: "Generated from today's verified stories")
                BDNCard {
                    Text("Card content lives here.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.primaryText)
                }
            }
        }
        .padding(20)
    }
    .background(AppTheme.pageBackground.ignoresSafeArea())
}

/// Small capsule for content provenance (one chip per card row where space allows).
struct ContentSourceChip: View {
    let label: ContentSourceLabel
    var body: some View {
        Text(label.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
            .accessibilityLabel("Content source: \(label.rawValue)")
    }

    private var foregroundColor: Color {
        Color.secondary
    }

    private var backgroundColor: Color {
        Color(.tertiarySystemFill)
    }
}
