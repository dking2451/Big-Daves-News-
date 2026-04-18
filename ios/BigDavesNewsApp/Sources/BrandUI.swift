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
        colors: [Color(hex: "F59E0B"), Color(hex: "EAB308")],
        startPoint: .leading,
        endPoint: .trailing
    )
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

struct BrandCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: primaryShadowColor, radius: 8, x: 0, y: 4)
    }

    private var bevelStrokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.black.opacity(0.24)]
        }
        return [Color.white.opacity(0.75), Color.black.opacity(0.12)]
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.20) : Color.black.opacity(0.10)
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
            .background(AppTheme.primaryGradient.opacity(configuration.isPressed ? 0.88 : 1))
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
