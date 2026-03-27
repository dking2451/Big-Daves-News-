import SwiftUI

// MARK: - Layout tokens (Watch)

/// Shared spacing, corner radii, and metrics for Watch screens — keeps cards, toolbars, and actions aligned.
enum WatchDesign {
    /// Small spacing (tight stacks).
    static let spaceXS: CGFloat = 8
    /// Medium spacing (rails, header-to-content gap).
    static let spaceSM: CGFloat = 12
    /// Standard internal card padding.
    static let spaceMD: CGFloat = 16
    /// Section spacing (major breaks).
    static let spaceSection: CGFloat = 24

    /// Badges and compact icon controls.
    static let radiusBadge: CGFloat = 12
    /// Text buttons and stacked “small” cards (horizontal strip).
    static let radiusControl: CGFloat = 16
    /// Hero surfaces and full detail cards.
    static let radiusCardLarge: CGFloat = 20

    static let toolbarTapSize: CGFloat = 44
    static let toolbarIconFont: Font = .system(size: 17, weight: .semibold)

    /// Shared minimum height for card CTAs and icon actions at default Dynamic Type (grows at accessibility sizes).
    static let cardActionMinHeight: CGFloat = 44
}

// MARK: - Typography (Watch)

enum WatchType {
    /// Section titles (`WatchSectionHeader` already scales; this is for inline reuse).
    static func sectionTitle(for dynamic: DynamicTypeSize) -> Font {
        if dynamic >= .accessibility3 { return .title3.weight(.bold) }
        if dynamic >= .accessibility1 { return .title2.weight(.bold) }
        return .title3.weight(.bold)
    }

    /// Titles on full detail / carousel cards.
    static func detailCardTitle(isPad: Bool, dynamic: DynamicTypeSize) -> Font {
        if isPad {
            if dynamic >= .accessibility3 { return .title2.weight(.semibold) }
            return .title3.weight(.semibold)
        }
        if dynamic >= .accessibility3 { return .title3.weight(.semibold) }
        return .headline.weight(.semibold)
    }

    /// Horizontal mini cards (“From Your List” strip) — same family as detail titles, scaled for narrow width.
    static func miniCardTitle(dynamic: DynamicTypeSize) -> Font {
        if dynamic >= .accessibility3 { return .title3.weight(.semibold) }
        if dynamic >= .accessibility1 { return .headline.weight(.semibold) }
        return .subheadline.weight(.semibold)
    }

    /// Provider / metadata line on cards.
    static func providerLine(isPad: Bool, isLargePad: Bool) -> Font {
        if isLargePad { return .subheadline.weight(.semibold) }
        if isPad { return .caption.weight(.semibold) }
        return .caption.weight(.semibold)
    }

    /// Sentence-style recommendation reason.
    static var reasonLine: Font { .caption.weight(.semibold) }

    /// Primary / secondary text CTA on cards and hero.
    static var cardButtonLabel: Font { .subheadline.weight(.semibold) }
}

// MARK: - Toolbar (navigation bar)

/// Icon-only control with shared fill, radius, and tap target for the Watch navigation bar group.
struct WatchToolbarIconChrome: View {
    let systemName: String
    var foreground: Color = AppTheme.secondaryText

    var body: some View {
        Image(systemName: systemName)
            .font(WatchDesign.toolbarIconFont)
            .foregroundStyle(foreground)
            .frame(width: WatchDesign.toolbarTapSize, height: WatchDesign.toolbarTapSize)
    }
}

struct WatchToolbarChromeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: WatchDesign.radiusBadge, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .overlay(
                RoundedRectangle(cornerRadius: WatchDesign.radiusBadge, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        lineWidth: 1
                    )
            )
    }
}

/// Trailing toolbar button (refresh, help, custom action).
struct WatchToolbarButton: View {
    let systemName: String
    var role: AppToolbarIconRole = .neutral
    var accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void

    private var foreground: Color {
        switch role {
        case .location: return AppTheme.accent
        case .refresh: return AppTheme.primary
        case .neutral: return AppTheme.secondaryText
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                WatchToolbarChromeBackground()
                WatchToolbarIconChrome(systemName: systemName, foreground: foreground)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Menu label matching `WatchToolbarButton` chrome (e.g. overflow).
struct WatchToolbarMenuLabel: View {
    let systemName: String
    var foreground: Color = AppTheme.secondaryText

    var body: some View {
        ZStack {
            WatchToolbarChromeBackground()
            WatchToolbarIconChrome(systemName: systemName, foreground: foreground)
        }
    }
}

#if DEBUG
/// Rank debug (DEBUG builds): same chrome and tap target as other Watch toolbar controls.
struct WatchToolbarRankDebugButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                WatchToolbarChromeBackground()
                WatchToolbarIconChrome(
                    systemName: "ladybug",
                    foreground: isOn ? AppTheme.primary : AppTheme.secondaryText
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rank debug")
        .accessibilityHint("Next refresh requests rank_debug when the API allows it.")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("Next refresh: request rank_debug (API needs ALLOW_WATCH_RANK_DEBUG=1)")
    }
}
#endif

// MARK: - Card CTA buttons (shared geometry)

/// Filled primary CTA — same min height as ``WatchSecondaryButton``; emphasis is color, not size.
struct WatchPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var minHeight: CGFloat {
        dynamicTypeSize >= .accessibility3 ? 52 : WatchDesign.cardActionMinHeight
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.titleAndIcon)
            .font(WatchType.cardButtonLabel)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, WatchDesign.spaceXS)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentColor)
        .controlSize(.regular)
    }
}

/// Bordered secondary CTA — pairs with ``WatchPrimaryButton`` (hero bar, same card row).
struct WatchSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    /// Hero action bar sits on a dark material; use white border/fill semantics. Cards on system background use `false`.
    var onDarkChrome: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var minHeight: CGFloat {
        dynamicTypeSize >= .accessibility3 ? 52 : WatchDesign.cardActionMinHeight
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(WatchType.cardButtonLabel)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .padding(.horizontal, WatchDesign.spaceXS)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.bordered)
        .tint(onDarkChrome ? .white : Color.primary)
        .foregroundStyle(onDarkChrome ? Color.white : Color.primary)
        .controlSize(.regular)
    }
}
