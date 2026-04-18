import SwiftUI

// MARK: - Design tokens (single source; spacing 8 / 12 / 16 / 24)

enum TVLayout {
    enum Spacing {
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s24: CGFloat = 24
    }

    /// Small surfaces (badges, small media frames).
    static let radiusSmall: CGFloat = 12
    /// Buttons (`bordered` / `borderedProminent`).
    static let radiusButton: CGFloat = 16
    /// Poster and sports cards.
    static let radiusCard: CGFloat = 20

    /// Between rails / major vertical stacks (standard section rhythm).
    static let sectionGap: CGFloat = Spacing.s24

    /// Placeholder glyph inside poster-sized frames (one size app-wide).
    static let placeholderIconSize: CGFloat = 52
    /// First content inset below navigation chrome.
    static let screenTopInset: CGFloat = Spacing.s24
    /// Horizontal inset for scroll pages (24 + 24 + 12 = 60).
    static let contentGutter: CGFloat = Spacing.s24 + Spacing.s24 + Spacing.s12

    static let heroHeight: CGFloat = 620
    static let detailBackdropHeight: CGFloat = 520
    static let ochoHeaderHeight: CGFloat = 360

    static let cardPosterWidth: CGFloat = 280
    static let cardPosterHeight: CGFloat = 420

    static let buttonMaxWidth: CGFloat = 520

    /// Centered empty states (24×6 + 16 = 160).
    static let emptyStateTopInset: CGFloat = Spacing.s24 * 6 + Spacing.s16

    static let appBackground = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let heroPlaceholderFill = Color(red: 0.08, green: 0.1, blue: 0.14)
}

enum TVTheme {
    static let accent = Color(red: 0.25, green: 0.62, blue: 0.72)
    static let heroGradientTop = Color.black.opacity(0.15)
    static let heroGradientBottom = Color.black.opacity(0.92)
    static let cardBackground = Color.white.opacity(0.06)
}

/// Purple accent and chrome **only** for THE OCHO tab (all other tabs stay teal).
enum TVOchoTheme {
    static let accent = Color(red: 0.58, green: 0.38, blue: 0.95)
    static let background = Color(red: 0.035, green: 0.04, blue: 0.075)
    static let headerGlow = Color(red: 0.42, green: 0.22, blue: 0.72).opacity(0.45)
}

// MARK: - Focus motion (interaction-only; layout tokens unchanged)

enum TVFocusMotion {
    /// 200ms, ease-out — within Apple TV–comfortable 150–250ms range.
    static let animation = Animation.easeOut(duration: 0.2)
    static let brightness: CGFloat = 0.065
}

/// Presets: **buttons** vs **cards** only — same-scale CTAs everywhere; cards share one lift.
enum TVFocusInteractionStyle {
    /// Bordered / prominent controls (identical metrics for primary, secondary, toolbar, hero CTAs).
    case button
    /// Poster and sports cards.
    case card
    /// Deprecated alias for `button` — keeps call sites readable; metrics match `.button`.
    case hero

    fileprivate var scale: CGFloat {
        switch self {
        case .button, .hero: return 1.07
        case .card: return 1.085
        }
    }

    fileprivate var shadowRadius: CGFloat {
        switch self {
        case .button, .hero: return 10
        case .card: return 14
        }
    }

    fileprivate var shadowOpacity: Double {
        switch self {
        case .button, .hero: return 0.24
        case .card: return 0.3
        }
    }

    fileprivate var shadowYOffset: CGFloat {
        switch self {
        case .button, .hero: return 4
        case .card: return 6
        }
    }

    fileprivate var brightness: CGFloat {
        TVFocusMotion.brightness
    }
}

struct TVFocusScaleStyle: ViewModifier {
    @Environment(\.isFocused) private var focused

    var scale: CGFloat
    var brightness: CGFloat
    var shadowRadius: CGFloat
    var shadowOpacity: Double
    var shadowYOffset: CGFloat

    init(style: TVFocusInteractionStyle) {
        scale = style.scale
        brightness = style.brightness
        shadowRadius = style.shadowRadius
        shadowOpacity = style.shadowOpacity
        shadowYOffset = style.shadowYOffset
    }

    init(scale: CGFloat, brightness: CGFloat? = nil, shadowRadius: CGFloat = 12, shadowOpacity: Double = 0.26, shadowYOffset: CGFloat = 5) {
        self.scale = scale
        self.brightness = brightness ?? TVFocusMotion.brightness
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
        self.shadowYOffset = shadowYOffset
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(focused ? scale : 1.0, anchor: .center)
            .brightness(focused ? brightness : 0)
            .shadow(
                color: Color.black.opacity(focused ? shadowOpacity : 0),
                radius: focused ? shadowRadius : 0,
                x: 0,
                y: focused ? shadowYOffset : 0
            )
            .animation(TVFocusMotion.animation, value: focused)
    }
}

extension View {
    /// Preferred: use design-system focus presets (scale, brighten, soft shadow).
    func tvFocusInteractive(_ style: TVFocusInteractionStyle = .card) -> some View {
        modifier(TVFocusScaleStyle(style: style))
    }

    /// Escape hatch — keeps brightness + easing + shadow proportional to a custom scale.
    func tvFocusScale(_ scale: CGFloat) -> some View {
        let shadowR = 8 + (scale - 1) * 120
        let shadowY = 3 + (scale - 1) * 40
        return modifier(
            TVFocusScaleStyle(
                scale: scale,
                shadowRadius: min(22, max(8, shadowR)),
                shadowOpacity: min(0.34, 0.18 + Double(scale - 1) * 0.9),
                shadowYOffset: min(10, max(3, shadowY))
            )
        )
    }
}

// MARK: - Badge (status / labels — shared capsule geometry)

struct TVBadge: View {
    let text: String
    var style: Style
    /// Capsule chips read best uppercase; callers can disable for sentence case.
    var usesUppercase: Bool = true

    enum Style {
        case live
        case startingSoon
        case scheduled

        var foreground: Color {
            switch self {
            case .live: return Color.red
            case .startingSoon: return Color.yellow
            case .scheduled: return Color.secondary
            }
        }

        var fill: Color {
            switch self {
            case .live: return Color.red
            case .startingSoon: return Color.yellow
            case .scheduled: return Color.white.opacity(0.25)
            }
        }
    }

    var body: some View {
        Group {
            if usesUppercase {
                Text(text)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
            } else {
                Text(text)
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(style.foreground)
        .padding(.horizontal, TVLayout.Spacing.s8)
        .padding(.vertical, TVLayout.Spacing.s8 / 2)
        .background(Capsule(style: .continuous).fill(style.fill.opacity(0.35)))
    }
}

// MARK: - Section header

struct TVSectionHeader: View {
    let title: String
    var subtitle: String?
    /// When set (Ocho only), tints the subtitle without changing layout or title style.
    var subtitleTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: TVLayout.Spacing.s8) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(subtitleTint ?? Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty / error messaging (centered text + optional retry; uses layout tokens only)

struct TVEmptyStateMessage: View {
    let title: String
    let subtitle: String
    var retryTitle: String? = nil
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: TVLayout.Spacing.s16) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retryTitle, let retryAction {
                HStack {
                    Spacer(minLength: 0)
                    TVPrimaryButton(title: retryTitle, action: retryAction)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, TVLayout.emptyStateTopInset)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TVLayout.contentGutter + TVLayout.Spacing.s12)
    }
}

enum TVShellErrorCopy {
    static let title = "Something went wrong"
    static let subtitle = "Please try again."
}

/// Sports + Ocho use identical rail subtitles for the same concepts.
enum TVSportsRailCopy {
    static let liveSubtitle = "Games in progress"
    static let startingSoonSubtitle = "Next hour or two"
    static let tonightSubtitle = "Later today"
}

// MARK: - Buttons (unified width, padding, and corner — `TVToolbarButton` = same chrome as secondary)

private enum TVButtonMetrics {
    static let maxWidth = TVLayout.buttonMaxWidth
    static let verticalPadding = TVLayout.Spacing.s16
    static let horizontalPadding = TVLayout.Spacing.s24
}

/// Primary filled CTA (teal by default). Use Ocho tint only on THE OCHO tab.
struct TVPrimaryButton: View {
    let title: String
    var tint: Color = TVTheme.accent
    var focusStyle: TVFocusInteractionStyle = .button
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: TVButtonMetrics.maxWidth)
                .padding(.horizontal, TVButtonMetrics.horizontalPadding)
                .padding(.vertical, TVButtonMetrics.verticalPadding)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: TVLayout.radiusButton))
        .tint(tint)
        .tvFocusInteractive(focusStyle)
    }
}

/// Secondary bordered action — detail screens, hero “View details”, etc.
struct TVSecondaryButton: View {
    let title: String
    var accessibilityLabel: String?
    var tint: Color = TVTheme.accent
    var focusStyle: TVFocusInteractionStyle = .button
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: TVButtonMetrics.maxWidth)
                .padding(.horizontal, TVButtonMetrics.horizontalPadding)
                .padding(.vertical, TVButtonMetrics.verticalPadding)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: TVLayout.radiusButton))
        .tint(tint)
        .tvFocusInteractive(focusStyle)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// Navigation / toolbar-scoped control — **same metrics** as `TVSecondaryButton` (single interaction target size).
struct TVToolbarButton: View {
    let title: String
    var accessibilityLabel: String?
    var tint: Color = TVTheme.accent
    var focusStyle: TVFocusInteractionStyle = .button
    let action: () -> Void

    var body: some View {
        TVSecondaryButton(title: title, accessibilityLabel: accessibilityLabel, tint: tint, focusStyle: focusStyle, action: action)
    }
}

// MARK: - Poster card

struct TVPosterCard: View {
    let show: TVWatchShowItem
    let action: () -> Void
    var footnote: String?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                ZStack {
                    RoundedRectangle(cornerRadius: TVLayout.radiusCard, style: .continuous)
                        .fill(TVTheme.cardBackground)
                    poster
                }
                .frame(width: TVLayout.cardPosterWidth, height: TVLayout.cardPosterHeight)
                .clipShape(RoundedRectangle(cornerRadius: TVLayout.radiusCard, style: .continuous))
                Text(show.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: TVLayout.cardPosterWidth, alignment: .leading)
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .tvFocusInteractive(.card)
        .accessibilityLabel(show.title)
    }

    @ViewBuilder private var poster: some View {
        if let url = show.posterRemoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    ProgressView()
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "tv.inset.filled")
            .font(.system(size: TVLayout.placeholderIconSize))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Content rail

struct TVContentRail<Content: View>: View {
    let title: String
    var subtitle: String?
    var subtitleTint: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: TVLayout.Spacing.s16) {
            TVSectionHeader(title: title, subtitle: subtitle, subtitleTint: subtitleTint)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: TVLayout.Spacing.s24) {
                    content()
                }
                .padding(.horizontal, TVLayout.Spacing.s16)
                .padding(.vertical, TVLayout.Spacing.s8)
            }
        }
    }
}

// MARK: - Hero

struct TVHeroShowcaseView: View {
    let show: TVWatchShowItem
    let reason: String?
    let primaryTitle: String
    let onPrimary: () -> Void
    var onDetails: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackdrop
            LinearGradient(
                colors: [TVTheme.heroGradientTop, TVTheme.heroGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                Spacer()
                Text(show.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                if let p = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                    Text(p)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                }
                TVPrimaryButton(title: primaryTitle, action: onPrimary)
                TVSecondaryButton(title: "View details", accessibilityLabel: "View details") {
                    onDetails()
                }
            }
            .padding(.horizontal, TVLayout.contentGutter)
            .padding(.bottom, TVLayout.Spacing.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: TVLayout.heroHeight)
        .frame(maxWidth: .infinity)
    }

    private var heroBackdrop: some View {
        Group {
            if let url = show.posterRemoteURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        TVLayout.heroPlaceholderFill
                    }
                }
            } else {
                TVLayout.heroPlaceholderFill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
