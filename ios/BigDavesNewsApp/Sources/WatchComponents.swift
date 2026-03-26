import SwiftUI

// MARK: - List scope (All / Seen / My Likes)

enum WatchListScope: String, CaseIterable, Identifiable {
    case all = "All"
    case seen = "Seen"
    case myLikes = "My Likes"

    var id: String { rawValue }

    var accessibilityHint: String {
        switch self {
        case .all: return "Shows personalized recommendations."
        case .seen: return "Only shows you’ve marked as seen."
        case .myLikes: return "Only shows you gave a thumbs up."
        }
    }

    var detailFooter: String {
        switch self {
        case .all: return "Personalized picks. Use “Include watched” to show titles you’ve already finished."
        case .seen: return "Only shows you’ve marked as seen."
        case .myLikes: return "Only shows you’ve given a thumbs up."
        }
    }
}

// MARK: - Match % (batch-relative from trend scores)

enum WatchScoreFormatting {
    /// Maps `trendScore` to 0–100 within the current batch so “Match” reads as a relative fit, not an arbitrary number.
    static func matchPercent(for show: WatchShowItem, in batch: [WatchShowItem]) -> Int {
        guard !batch.isEmpty else { return 72 }
        let scores = batch.map(\.trendScore)
        guard let minS = scores.min(), let maxS = scores.max(), maxS > minS else {
            return min(100, max(0, Int(show.trendScore.rounded())))
        }
        let t = (show.trendScore - minS) / (maxS - minS)
        return min(100, max(0, Int((t * 100).rounded())))
    }
}

// MARK: - Poster (trusted TMDB only; premium placeholder for all other API states)

/// Shared art placeholder: same premium treatment for `missing`, `unresolved_low_confidence`, and `unverified_remote`.
struct WatchPremiumPosterPlaceholder: View {
    let displayKind: WatchPosterDisplayStatus
    let title: String
    var cornerRadius: CGFloat = 14
    var continuousCornerStyle: Bool = true
    var symbolFont: Font = .title2
    var symbolName: String = "tv.fill"
    var showProgress: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: continuousCornerStyle ? .continuous : .circular
            )
            .fill(Color(.secondarySystemFill))

            LinearGradient(
                colors: [
                    AppTheme.primary.opacity(colorScheme == .dark ? 0.42 : 0.24),
                    AppTheme.accent.opacity(colorScheme == .dark ? 0.28 : 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if showProgress {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: symbolName)
                    .font(symbolFont)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: continuousCornerStyle ? .continuous : .circular)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        switch displayKind {
        case .trusted:
            return ""
        case .missing:
            return "No poster available for this series."
        case .unresolvedLowConfidence:
            return "Poster withheld: title could not be matched with high confidence."
        case .unverifiedRemote:
            return "Poster withheld: image source is not verified."
        }
    }
}

private struct WatchShowPosterImage: View {
    let show: WatchShowItem
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    var continuousCornerStyle: Bool = true
    var showProgressWhenLoading: Bool = true
    var placeholderSymbolFont: Font = .title2

    var body: some View {
        Group {
            if let url = show.posterRemoteImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder(showProgress: showProgressWhenLoading)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder(showProgress: false)
                    @unknown default:
                        placeholder(showProgress: false)
                    }
                }
            } else {
                placeholder(showProgress: false)
            }
        }
        .frame(width: width, height: height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: continuousCornerStyle ? .continuous : .circular
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(show.title)
        .accessibilityHint(accessibilityHintText)
    }

    @ViewBuilder
    private func placeholder(showProgress: Bool) -> some View {
        WatchPremiumPosterPlaceholder(
            displayKind: show.posterDisplayKind,
            title: show.title,
            cornerRadius: cornerRadius,
            continuousCornerStyle: continuousCornerStyle,
            symbolFont: placeholderSymbolFont,
            symbolName: "tv.fill",
            showProgress: showProgress
        )
    }

    private var accessibilityHintText: String {
        if let _ = show.posterRemoteImageURL {
            return "Show poster image."
        }
        switch show.posterDisplayKind {
        case .trusted:
            return "Show poster image."
        case .missing:
            return "No poster available for this series."
        case .unresolvedLowConfidence:
            return "Poster withheld: title could not be matched with high confidence."
        case .unverifiedRemote:
            return "Poster withheld: image source is not verified."
        }
    }
}

// MARK: - New Episode badge row (shared)

struct WatchNewEpisodeBadgeRow: View {
    let show: WatchShowItem
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if show.isNewEpisode == true {
                Text(show.releaseBadgeLabel ?? "Recently aired")
                    .font(prominent ? .caption.weight(.bold) : .caption2.weight(.bold))
                    .padding(.horizontal, prominent ? 10 : 8)
                    .padding(.vertical, prominent ? 6 : 4)
                    .background(Color.green.opacity(0.22))
                    .foregroundStyle(Color.green)
                    .clipShape(Capsule())
                    .accessibilityLabel(show.releaseBadgeLabel ?? "Recently aired")
            } else if let badge = WatchShowCardHelpers.resolvedReleaseBadge(for: show) {
                let isNew = show.releaseBadge?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "new"
                Text(isNew ? (show.releaseBadgeLabel ?? "Recently aired") : badge)
                    .font(prominent ? .caption.weight(.bold) : .caption2.weight(.bold))
                    .padding(.horizontal, prominent ? 10 : 8)
                    .padding(.vertical, prominent ? 6 : 4)
                    .background((isNew ? Color.green : Color.orange).opacity(0.2))
                    .foregroundStyle(isNew ? Color.green : Color.orange)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - New Episodes carousel

struct WatchNewEpisodesCarousel: View {
    let items: [WatchShowItem]
    let onToggleSaved: (WatchShowItem, Bool) -> Void
    let onSelect: (WatchShowItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently aired for you")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("From shows you’ve saved, seen, or liked.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { show in
                        WatchNewEpisodeCarouselCard(show: show) {
                            onToggleSaved(show, !(show.saved ?? false))
                        } onTap: {
                            onSelect(show)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct WatchNewEpisodeCarouselCard: View {
    let show: WatchShowItem
    let onToggleSave: () -> Void
    let onTap: () -> Void

    private var w: CGFloat { DeviceLayout.isPad ? 132 : 120 }
    private var h: CGFloat { DeviceLayout.isPad ? 186 : 168 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                WatchShowPosterImage(
                    show: show,
                    width: w,
                    height: h,
                    cornerRadius: 12,
                    continuousCornerStyle: true,
                    showProgressWhenLoading: true,
                    placeholderSymbolFont: .title2
                )

                if show.isNewEpisode == true {
                    Text("Recent")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.92))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(8)
                        .accessibilityLabel(show.releaseBadgeLabel ?? "Recently aired")
                }
            }
            .onTapGesture { onTap() }

            Text(show.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(width: w, alignment: .leading)

            if let p = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                Label(p, systemImage: WatchProviderIcons.systemImage(for: p))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let first = show.providers.first {
                Label(first, systemImage: WatchProviderIcons.systemImage(for: first))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                onToggleSave()
            } label: {
                Label((show.saved ?? false) ? "Saved" : "Save", systemImage: (show.saved ?? false) ? "bookmark.fill" : "bookmark")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(width: w + 8)
    }
}

// MARK: - Icons (shared)

enum WatchProviderIcons {
    static func systemImage(for provider: String) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("all providers") { return "line.3.horizontal.decrease.circle" }
        if key.contains("netflix") { return "play.rectangle.fill" }
        if key.contains("hulu") { return "play.rectangle.fill" }
        if key.contains("prime") || key.contains("amazon") { return "cart.fill" }
        if key.contains("apple tv") { return "applelogo" }
        if key.contains("max") || key.contains("hbo") { return "tv.fill" }
        if key.contains("disney") { return "sparkles.tv.fill" }
        if key.contains("paramount") || key.contains("peacock") { return "tv.fill" }
        return "play.rectangle"
    }
}

enum WatchFilterIcons {
    static func genreIcon(for genre: String) -> String {
        let key = genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "all" { return "line.3.horizontal.decrease.circle" }
        if key == "seen" { return "checkmark.circle.fill" }
        if key == "my list" { return "bookmark.fill" }
        if key == "new episodes" { return "sparkles.tv.fill" }
        if key.contains("action") { return "bolt.fill" }
        if key.contains("comedy") { return "face.smiling" }
        if key.contains("drama") { return "theatermasks.fill" }
        if key.contains("crime") { return "shield.lefthalf.filled" }
        if key.contains("sci") { return "sparkles" }
        if key.contains("reality") { return "tv.fill" }
        if key.contains("documentary") { return "doc.text.fill" }
        if key.contains("animation") { return "paintpalette.fill" }
        return "tag.fill"
    }

    static func providerIcon(for provider: String) -> String {
        WatchProviderIcons.systemImage(for: provider)
    }
}

// MARK: - Split sidebar row

struct WatchSplitSidebarRow: View {
    let show: WatchShowItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WatchShowPosterImage(
                show: show,
                width: 48,
                height: 68,
                cornerRadius: 8,
                continuousCornerStyle: true,
                showProgressWhenLoading: true,
                placeholderSymbolFont: .body
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let p = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                    Text(p)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helpers for cards

enum WatchShowCardHelpers {
    static func resolvedReleaseBadge(for show: WatchShowItem) -> String? {
        if let backendLabel = show.releaseBadgeLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !backendLabel.isEmpty {
            return backendLabel
        }
        return fallbackReleaseBadge(releaseDate: show.releaseDate)
    }

    static func fallbackReleaseBadge(releaseDate: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: releaseDate) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let diff = Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0
        if diff < -14 { return nil }
        if diff <= 0 { return "Recently aired" }
        if diff <= 7 { return "This Week" }
        return "Upcoming"
    }
}

// MARK: - Show card (grid / phone)

struct WatchShowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let show: WatchShowItem
    let matchPercent: Int?
    let onToggleSeen: (Bool) -> Void
    let onReaction: (String) -> Void
    let onToggleSaved: (Bool) -> Void
    let onCaughtUp: () -> Void

    private var isPad: Bool { DeviceLayout.isPad }
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 104 : (isPad ? 92 : 72) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 146 : (isPad ? 128 : 104) }
    private var cardPadding: CGFloat { DeviceLayout.isLargePad ? 14 : (isPad ? 12 : 9) }
    private var cornerRadius: CGFloat { DeviceLayout.isLargePad ? 20 : (isPad ? 18 : 14) }
    private var metaFont: Font {
        if DeviceLayout.isLargePad { return .subheadline.weight(.semibold) }
        if isPad { return .caption.weight(.semibold) }
        return .caption2.weight(.semibold)
    }
    private var actionLabelFont: Font {
        if DeviceLayout.isLargePad { return .subheadline }
        return .caption
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WatchShowPosterImage(
                show: show,
                width: thumbWidth,
                height: thumbHeight,
                cornerRadius: 10,
                continuousCornerStyle: false,
                showProgressWhenLoading: true,
                placeholderSymbolFont: DeviceLayout.isLargePad ? .title3 : .callout
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(show.title)
                        .font(isPad ? .title3.weight(.semibold) : .headline)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let pct = matchPercent {
                        Text("Match: \(pct)%")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.14))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                            .accessibilityLabel("Match \(pct) percent")
                    }
                }

                primaryProviderLine

                WatchNewEpisodeBadgeRow(show: show, prominent: false)

                Text(show.seasonEpisodeStatus)
                    .font(DeviceLayout.isLargePad ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(show.synopsis)
                    .font(DeviceLayout.isLargePad ? .body : (isPad ? .subheadline : .caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(DeviceLayout.isLargePad ? 2 : 1)

                StreamingProviderLaunchControl(show: show, style: .cardCompact)
                    .frame(maxWidth: .infinity, alignment: .leading)

                actionRow
            }
        }
        .padding(cardPadding)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: bevelStrokeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: primaryShadowColor, radius: 12, x: 0, y: 5)
        .shadow(color: secondaryShadowColor, radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private var primaryProviderLine: some View {
        if let primary = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            Label(primary, systemImage: WatchProviderIcons.systemImage(for: primary))
                .font(metaFont)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
        } else if let first = show.providers.first {
            Label(first, systemImage: WatchProviderIcons.systemImage(for: first))
                .font(metaFont)
                .foregroundStyle(Color.primary)
        }
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    onToggleSaved(!(show.saved ?? false))
                } label: {
                    Image(systemName: (show.saved ?? false) ? "bookmark.fill" : "bookmark")
                        .font(DeviceLayout.isLargePad ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                        .frame(minWidth: 40, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel((show.saved ?? false) ? "Saved" : "Save to watchlist")

                Button {
                    onToggleSeen(!(show.seen ?? false))
                } label: {
                    Image(systemName: (show.seen ?? false) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(DeviceLayout.isLargePad ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                        .frame(minWidth: 40, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel((show.seen ?? false) ? "Seen" : "Mark as seen")

                Button {
                    onReaction((show.userReaction == "up") ? "none" : "up")
                } label: {
                    Label("\(show.upvotes ?? 0)", systemImage: show.userReaction == "up" ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(actionLabelFont)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.bordered)

                Button {
                    onReaction((show.userReaction == "down") ? "none" : "down")
                } label: {
                    Label("\(show.downvotes ?? 0)", systemImage: show.userReaction == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(actionLabelFont)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.bordered)

                if show.saved == true, show.isNewEpisode == true {
                    Button {
                        onCaughtUp()
                    } label: {
                        Label("Caught Up", systemImage: "checkmark.seal")
                            .font(actionLabelFont)
                            .frame(minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var bevelStrokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.black.opacity(0.22)]
        }
        return [Color.white.opacity(0.7), Color.black.opacity(0.10)]
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.10)
    }

    private var secondaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.14) : Color.black.opacity(0.05)
    }
}

// MARK: - Loading skeleton

struct WatchCardSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 112 : (DeviceLayout.isPad ? 96 : 72) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 156 : (DeviceLayout.isPad ? 132 : 104) }
    private var cardPadding: CGFloat { DeviceLayout.isLargePad ? 16 : (DeviceLayout.isPad ? 14 : 10) }
    private var cornerRadius: CGFloat { DeviceLayout.isLargePad ? 20 : (DeviceLayout.isPad ? 18 : 14) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemFill))
                .frame(width: thumbWidth, height: thumbHeight)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: DeviceLayout.isLargePad ? 220 : 160, height: 12)
            }
        }
        .padding(cardPadding)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: bevelStrokeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: primaryShadowColor, radius: 12, x: 0, y: 5)
        .shadow(color: secondaryShadowColor, radius: 3, x: 0, y: 1)
    }

    private var bevelStrokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.black.opacity(0.22)]
        }
        return [Color.white.opacity(0.7), Color.black.opacity(0.10)]
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.10)
    }

    private var secondaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.14) : Color.black.opacity(0.05)
    }
}
