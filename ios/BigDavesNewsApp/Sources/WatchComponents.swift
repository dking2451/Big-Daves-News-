import SwiftUI
import Foundation

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
    /// Minimum batch-relative match percent before we show any quality chip (avoids “Match: 3%” trust damage).
    static let matchQualityMinimumPercent = 60

    /// Maps batch-relative rank (or catalog trend when `rank_score` absent) to 0–100 — not a raw “% match”.
    static func matchPercent(for show: WatchShowItem, in batch: [WatchShowItem]) -> Int {
        guard !batch.isEmpty else { return 72 }
        let scores = batch.map(\.effectiveRankValue)
        let v = show.effectiveRankValue
        guard let minS = scores.min(), let maxS = scores.max(), maxS > minS else {
            return min(100, max(0, Int(v.rounded())))
        }
        let t = (v - minS) / (maxS - minS)
        return min(100, max(0, Int((t * 100).rounded())))
    }

    /// Human-readable match line for the card chrome, or `nil` when the score is too low to show.
    static func matchQualityLabel(for show: WatchShowItem, in batch: [WatchShowItem]) -> String? {
        matchQualityLabel(forPercent: matchPercent(for: show, in: batch))
    }

    static func matchQualityLabel(forPercent percent: Int) -> String? {
        guard percent >= matchQualityMinimumPercent else { return nil }
        switch percent {
        case 90...100: return "Great match"
        case 75..<90: return "Good pick"
        default: return "Worth a look"
        }
    }
}

// MARK: - Recommendation copy (hero + list; no raw low match %)

/// Trust-building, sentence-style reasons. Uses batch-relative quality labels only when strong (≥60%).
enum WatchCardRecommendation {
    /// Short, specific line for the hero (tonight’s pick); avoids generic “good pick” when we can be concrete.
    static func heroTagline(
        for show: WatchShowItem,
        rankingBatch: [WatchShowItem],
        savedBatch: [WatchShowItem]? = nil,
        isTonightsPick: Bool = false
    ) -> String {
        if let server = show.recommendationReason?.trimmingCharacters(in: .whitespacesAndNewlines), !server.isEmpty {
            return server
        }
        let saved = savedBatch ?? rankingBatch.filter { $0.saved == true }
        if show.saved == true, show.isNewEpisode == true {
            return "New episode from your list"
        }
        if show.saved == true {
            return "From your saved shows"
        }
        if let sibling = savedGenreSibling(for: show, saved: saved) {
            return "Because you saved \(sibling)"
        }
        if show.isNewEpisode == true {
            return "New episode available for you"
        }
        if let code = show.releaseBadge?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           code == "this_week" || code == "new" {
            return "Fresh release worth catching"
        }
        if let pg = show.primaryGenre?.trimmingCharacters(in: .whitespacesAndNewlines), !pg.isEmpty {
            let pl = pg.lowercased()
            if pl.contains("fantasy") { return "Because you like fantasy" }
            if pl.contains("thrill") { return "Popular with thriller fans" }
            return "Because you like \(pl)"
        }
        if let g = show.genres.first?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            let gl = g.lowercased()
            if gl.contains("fantasy") { return "Because you like fantasy" }
            if gl.contains("thrill") { return "Popular with thriller fans" }
            return "Because you like \(gl)"
        }
        if isTonightsPick {
            return "Top pick for tonight"
        }
        let prim = (show.primaryProvider ?? "").lowercased()
        if prim.contains("max") || prim.contains("hbo") {
            return "Top trending on Max"
        }
        if prim.contains("netflix") { return "Top trending on Netflix" }
        if prim.contains("apple") { return "A strong pick on Apple TV+" }
        return listReasonLine(for: show, listIndex: nil, rankingBatch: rankingBatch, badgeBatch: rankingBatch)
    }

    /// Hero and list share list logic; `listIndex == nil` skips “trending in list” phrasing.
    static func listReasonLine(
        for show: WatchShowItem,
        listIndex: Int?,
        rankingBatch: [WatchShowItem],
        badgeBatch: [WatchShowItem]
    ) -> String {
        if let server = show.recommendationReason?.trimmingCharacters(in: .whitespacesAndNewlines), !server.isEmpty {
            return server
        }
        let batch = rankingBatch.isEmpty ? [show] : rankingBatch

        if let anchor = likedTitleSharingGenre(with: show, in: batch) {
            return "Because you liked \(anchor)"
        }

        if batch.count >= 2, let q = WatchScoreFormatting.matchQualityLabel(for: show, in: batch) {
            switch q {
            case "Great match": return "Great match — worth prioritizing tonight"
            case "Good pick": return "Good pick for your taste"
            case "Worth a look": return "Worth a look tonight"
            default: break
            }
        }

        if show.genres.contains(where: { $0.lowercased().contains("thrill") }) {
            return "Popular with thriller fans"
        }

        if let primary = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            let lower = primary.lowercased()
            if lower.contains("apple") { return "A strong pick on Apple TV+" }
            if lower.contains("netflix") { return "A strong pick on Netflix" }
            if lower.contains("prime") || lower.contains("amazon") { return "A strong pick on Prime Video" }
            if lower.contains("hulu") { return "A strong pick on Hulu" }
            if lower.contains("max") || lower.contains("hbo") { return "A strong pick on Max" }
        }

        if let listIndex, listIndex < 3, badgeBatch.count > 3 {
            return "Trending in your recommendations"
        }

        if show.saved == true { return "From your saved shows" }
        if show.isNewEpisode == true { return "New episode ready to watch" }
        if show.userReaction == "up" { return "Based on shows you liked" }
        if show.watchProgressState == .finished { return "Trending — and you’ve finished this one before" }

        return "Worth considering tonight"
    }

    private static func savedGenreSibling(for show: WatchShowItem, saved: [WatchShowItem]) -> String? {
        guard !saved.isEmpty else { return nil }
        let genres = Set(show.genres.map { $0.lowercased() })
        guard !genres.isEmpty else { return nil }
        for other in saved where other.id != show.id {
            if other.genres.contains(where: { genres.contains($0.lowercased()) }) {
                return other.title
            }
        }
        return nil
    }

    private static func likedTitleSharingGenre(with show: WatchShowItem, in batch: [WatchShowItem]) -> String? {
        let genres = Set(show.genres.map { $0.lowercased() })
        guard !genres.isEmpty else { return nil }
        for other in batch where other.id != show.id && other.userReaction == "up" {
            if other.genres.contains(where: { g in genres.contains(g.lowercased()) }) {
                return other.title
            }
        }
        return nil
    }
}

// MARK: - Badges (standardized)

enum WatchListBadgeKind: Equatable {
    case tonight
    case new
    case newEpisode
    case recentlyAired
    case thisWeek
    case upcoming
    case trending

    fileprivate var title: String {
        switch self {
        case .tonight: return "Tonight"
        case .new: return "New"
        case .newEpisode: return "New episode"
        case .recentlyAired: return "Recently aired"
        case .thisWeek: return "This week"
        case .upcoming: return "Upcoming"
        case .trending: return "Trending"
        }
    }

    /// Compact strip cards use symbols only so narrow widths do not wrap badge text.
    fileprivate var systemImage: String {
        switch self {
        case .tonight: return "moon.stars.fill"
        case .new: return "sparkles"
        case .newEpisode: return "play.circle.fill"
        case .recentlyAired: return "dot.radiowaves.left.and.right"
        case .thisWeek: return "calendar"
        case .upcoming: return "clock"
        case .trending: return "chart.line.uptrend.xyaxis"
        }
    }

    fileprivate var fillOpacity: Double {
        switch self {
        case .tonight: return 0.88
        case .new: return 0.88
        case .newEpisode: return 0.9
        case .recentlyAired: return 0.88
        case .thisWeek: return 0.85
        case .upcoming: return 0.85
        case .trending: return 0.88
        }
    }

    fileprivate var capsuleColor: Color {
        switch self {
        case .tonight: return AppTheme.watchSecondaryAccent
        case .new: return Color.green
        case .newEpisode: return Color(red: 0.1, green: 0.55, blue: 0.35)
        case .recentlyAired: return Color.orange
        case .thisWeek: return Color.blue
        case .upcoming: return Color.cyan
        case .trending: return Color.orange
        }
    }
}

struct WatchBadgeView: View {
    let kind: WatchListBadgeKind
    var compact: Bool = false
    var useSolidFill: Bool = false
    /// When `true`, shows an SF Symbol instead of localized title (for narrow mini cards).
    var symbolOnly: Bool = false

    var body: some View {
        Group {
            if symbolOnly {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(useSolidFill ? Color.white : kind.capsuleColor)
                    .frame(width: 26, height: 26)
                    .background {
                        if useSolidFill {
                            Circle().fill(kind.capsuleColor.opacity(kind.fillOpacity))
                        } else {
                            Circle().fill(kind.capsuleColor.opacity(0.2))
                        }
                    }
                    .overlay {
                        if !useSolidFill {
                            Circle().strokeBorder(kind.capsuleColor.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .accessibilityLabel(kind.title)
            } else {
                Text(kind.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(useSolidFill ? Color.white : kind.capsuleColor)
                    .background {
                        if useSolidFill {
                            Capsule().fill(kind.capsuleColor.opacity(kind.fillOpacity))
                        } else {
                            Capsule().fill(kind.capsuleColor.opacity(0.18))
                        }
                    }
                    .overlay {
                        if !useSolidFill {
                            Capsule().strokeBorder(kind.capsuleColor.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .accessibilityLabel(kind.title)
            }
        }
    }
}

/// Preferred name in Watch UI code — same view as ``WatchBadgeView``.
typealias WatchBadge = WatchBadgeView

enum WatchBadgeFormatting {
    /// Single primary badge for list cards (priority: freshness > discovery).
    static func primaryBadge(for show: WatchShowItem, listIndex: Int?, in batch: [WatchShowItem]) -> WatchListBadgeKind? {
        if show.isNewEpisode == true {
            return .newEpisode
        }
        let code = show.releaseBadge?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if code == "new" {
            return .new
        }
        if code == "this_week" {
            return .thisWeek
        }
        if code == "upcoming" {
            return .upcoming
        }
        if let text = WatchShowCardHelpers.resolvedReleaseBadge(for: show) {
            let lower = text.lowercased()
            if lower.contains("recent") { return .recentlyAired }
            if lower.contains("this week") { return .thisWeek }
            if lower.contains("upcoming") { return .upcoming }
        }
        if let listIndex, listIndex < 3, show.trendScore >= 72, batch.count > 3 {
            return .trending
        }
        return nil
    }
}

struct WatchCardBadgeRow: View {
    let show: WatchShowItem
    var listIndex: Int? = nil
    var batch: [WatchShowItem] = []
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let kind = WatchBadgeFormatting.primaryBadge(for: show, listIndex: listIndex, in: batch) {
                WatchBadgeView(kind: kind, compact: !prominent, useSolidFill: false)
            }
        }
    }
}

// MARK: - Card actions (neutral chrome; purple reserved for Open in provider)

struct WatchCardIconAction: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void
    var subtitle: String?

    private var minTouchHeight: CGFloat {
        dynamicTypeSize >= .accessibility3 ? 52 : WatchDesign.cardActionMinHeight
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                // Show vote count only — no text label so all buttons stay the same fixed width.
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 56)
            .frame(minHeight: minTouchHeight)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: WatchDesign.radiusBadge, style: .continuous)
                    .fill(isOn ? Color(.tertiarySystemFill) : Color(.secondarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: WatchDesign.radiusBadge, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isOn ? (colorScheme == .dark ? 0.16 : 0.14) : (colorScheme == .dark ? 0.1 : 0.08)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        if let subtitle, !subtitle.isEmpty, Int(subtitle) != nil {
            return "\(title), \(subtitle)"
        }
        return title
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
    /// Short caption so missing art reads as intentional, not a broken load.
    var showsNoPreviewCaption: Bool = true
    /// Caption text opacity (hero uses a lower value for a quieter label).
    var captionOpacity: Double = 0.88

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: continuousCornerStyle ? .continuous : .circular
            )
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.watchCanvasDark.opacity(colorScheme == .dark ? 1.0 : 0.92),
                        Color(red: 0.04, green: 0.05, blue: 0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.45 : 0.3),
                    AppTheme.watchSecondaryAccent.opacity(colorScheme == .dark ? 0.18 : 0.1),
                    Color.black.opacity(colorScheme == .dark ? 0.55 : 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if showProgress {
                ProgressView()
                    .tint(.white)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: symbolName)
                        .font(symbolFont)
                        .foregroundStyle(.white.opacity(min(0.92, captionOpacity + 0.4)))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
                    if showsNoPreviewCaption {
                        Text("Preview unavailable")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(captionOpacity))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                }
                .accessibilityElement(children: .ignore)
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

struct WatchShowPosterImage: View {
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

// MARK: - Screen chrome (compact header + section titles)

/// Top-of-screen title row with **My List** + **Filter** + Help (no chips on canvas).
struct WatchCompactScreenHeader: View {
    let title: String
    var showsFilterDot: Bool = false
    /// Narrow sidebars (iPad split) use a slightly smaller title.
    var compact: Bool = false
    /// When false, only the title is shown (toolbar owns actions).
    var showsToolbarControls: Bool = true
    /// When set, **My List** presents full-screen (e.g. iPad split sidebar). When `nil`, uses `NavigationLink` push.
    var onMyListTap: (() -> Void)? = nil
    let onFilter: () -> Void
    var onInfoTap: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At XL Dynamic Type and up, step down from large title and stack the filter row so nothing clips.
    private var useStackedLayout: Bool {
        dynamicTypeSize >= .accessibility1
    }

    private var titleFont: Font {
        if compact {
            if dynamicTypeSize >= .accessibility3 { return .title3.weight(.bold) }
            if dynamicTypeSize >= .accessibility1 { return .title2.weight(.bold) }
            if dynamicTypeSize >= .xxxLarge { return .title.weight(.bold) }
            return .title2.weight(.bold)
        }
        if dynamicTypeSize >= .accessibility3 { return .title2.weight(.bold) }
        if dynamicTypeSize >= .accessibility1 { return .title.weight(.bold) }
        if dynamicTypeSize >= .xxxLarge { return .title.weight(.bold) }
        return .largeTitle.weight(.bold)
    }

    var body: some View {
        Group {
            if useStackedLayout {
                VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if showsToolbarControls {
                        HStack {
                            Spacer(minLength: 0)
                            trailingControls
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: WatchDesign.spaceSM) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.88)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsToolbarControls {
                        trailingControls
                    }
                }
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 6) {
            myListControl
            filterButton
            infoButton
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var myListControl: some View {
        if let onMyListTap {
            Button(action: onMyListTap) {
                AppToolbarIcon(systemName: "bookmark.fill", role: .neutral)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("My List")
            .accessibilityHint("Opens shows you saved on Watch.")
        } else {
            NavigationLink(value: WatchMyListRoute.list) {
                AppToolbarIcon(systemName: "bookmark.fill", role: .neutral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("My List")
            .accessibilityHint("Opens shows you saved on Watch.")
        }
    }

    private var filterButton: some View {
        Button(action: onFilter) {
            ZStack(alignment: .topTrailing) {
                AppToolbarIcon(systemName: "line.3.horizontal.decrease", role: .neutral)
                if showsFilterDot {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Filters")
        .accessibilityHint(
            showsFilterDot
                ? "Filters are active. Opens filter options."
                : "Opens filter options for genres and providers."
        )
    }

    private var infoButton: some View {
        Button {
            onInfoTap?()
        } label: {
            AppToolbarIcon(systemName: "info.circle", role: .neutral)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("How Watch works")
    }
}

struct WatchSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var titleFont: Font {
        if dynamicTypeSize >= .accessibility3 { return .title3.weight(.bold) }
        if dynamicTypeSize >= .accessibility1 { return .title2.weight(.bold) }
        return .title3.weight(.bold)
    }

    private var subtitleFont: Font {
        dynamicTypeSize >= .accessibility2 ? .subheadline : .caption
    }

    private var subtitleLineLimit: Int {
        dynamicTypeSize >= .accessibility3 ? 4 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(subtitleLineLimit)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mini card (horizontal strip — From Your List)

/// Narrow vertical layout sharing detail-card poster radius, badges, provider line, and the same provider CTA metrics as ``WatchShowCard``.
struct WatchMiniCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let show: WatchShowItem
    var listIndex: Int
    var batch: [WatchShowItem]

    private let posterWidth: CGFloat = 148
    private let posterHeight: CGFloat = 112

    private var titleLineLimit: Int {
        dynamicTypeSize >= .accessibility2 ? 3 : 2
    }

    private var titleBlockMinHeight: CGFloat {
        if dynamicTypeSize >= .accessibility3 { return 56 }
        if dynamicTypeSize >= .accessibility1 { return 48 }
        return 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchDesign.spaceXS) {
            ZStack(alignment: .topTrailing) {
                WatchShowPosterImage(
                    show: show,
                    width: posterWidth,
                    height: posterHeight,
                    cornerRadius: WatchDesign.radiusBadge,
                    continuousCornerStyle: false,
                    showProgressWhenLoading: true,
                    placeholderSymbolFont: .callout
                )

                if let kind = WatchBadgeFormatting.primaryBadge(for: show, listIndex: listIndex, in: batch) {
                    WatchBadge(kind: kind, compact: true, useSolidFill: false, symbolOnly: true)
                        .padding(6)
                }
            }
            .frame(width: posterWidth, height: posterHeight)

            Text(show.title)
                .font(WatchType.miniCardTitle(dynamic: dynamicTypeSize))
                .foregroundStyle(.primary)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.82)
                .frame(width: posterWidth, alignment: .leading)
                .frame(minHeight: titleBlockMinHeight, alignment: .topLeading)

            if let p = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                Text(p)
                    .font(WatchType.providerLine(isPad: false, isLargePad: false))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: posterWidth, alignment: .leading)
            } else {
                Color.clear
                    .frame(width: posterWidth, height: 16)
            }

            StreamingProviderLaunchControl(show: show, style: .miniCard)
                .frame(width: posterWidth, alignment: .leading)
        }
        .padding(WatchDesign.spaceMD)
        .frame(width: posterWidth + WatchDesign.spaceMD * 2, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: WatchDesign.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WatchDesign.radiusControl, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - New Episode badge row (shared)

struct WatchNewEpisodeBadgeRow: View {
    let show: WatchShowItem
    var prominent: Bool = false
    var listIndex: Int? = nil
    var batch: [WatchShowItem] = []

    var body: some View {
        WatchCardBadgeRow(show: show, listIndex: listIndex, batch: batch, prominent: prominent)
    }
}

// MARK: - New Episodes carousel

private enum WatchNewEpisodeCarouselSlotWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Horizontal strip of full-width ``WatchShowCard``s so layout matches **More Picks** (open, save, reactions) without squeezing the provider ``Menu``.
struct WatchNewEpisodesCarousel: View {
    let items: [WatchShowItem]
    let rankingBatch: [WatchShowItem]
    let onToggleSaved: (WatchShowItem, Bool) -> Void
    let onSelect: (WatchShowItem) -> Void
    let onCycleWatchProgress: (WatchShowItem) -> Void
    let onReaction: (WatchShowItem, String) -> Void
    let onCaughtUp: (WatchShowItem) -> Void

    @State private var measuredSlotWidth: CGFloat = 0

    private var fallbackCardWidth: CGFloat {
        let screen = UIScreen.main.bounds.width
        let inset = DeviceLayout.horizontalPadding * 2 + 20
        return min(DeviceLayout.contentMaxWidth, max(300, screen - inset))
    }

    private var cardWidth: CGFloat {
        let slot = measuredSlotWidth > 1 ? measuredSlotWidth : fallbackCardWidth
        return max(300, min(DeviceLayout.contentMaxWidth, slot - 8))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: WatchDesign.spaceSM) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, show in
                    WatchShowCard(
                        show: show,
                        recommendationReason: WatchCardRecommendation.listReasonLine(
                            for: show,
                            listIndex: index,
                            rankingBatch: rankingBatch,
                            badgeBatch: items
                        ),
                        listIndex: index,
                        badgeBatch: items,
                        onCycleWatchProgress: { onCycleWatchProgress(show) },
                        onReaction: { onReaction(show, $0) },
                        onToggleSaved: { onToggleSaved(show, $0) },
                        onCaughtUp: { onCaughtUp(show) }
                    )
                    .frame(width: cardWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(show)
                    }
                }
            }
            .padding(.vertical, WatchDesign.spaceXS / 2)
        }
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                Color.clear.preference(
                    key: WatchNewEpisodeCarouselSlotWidthKey.self,
                    value: geo.size.width
                )
            }
        }
        .onPreferenceChange(WatchNewEpisodeCarouselSlotWidthKey.self) { newWidth in
            guard newWidth > 1 else { return }
            if abs(newWidth - measuredSlotWidth) > 0.5 {
                measuredSlotWidth = newWidth
            }
        }
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


// MARK: - Watch progress badge (My List + cards)

struct WatchListProgressBadge: View {
    let state: WatchProgressState

    var body: some View {
        if state != .notStarted {
            Text(state.displayTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.secondary)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .accessibilityLabel("Status: \(state.displayTitle)")
        }
    }
}

// MARK: - My List habit helpers (selection + urgency)

enum WatchMyListHabit {
    /// Picks one saved title for “Start Watching”: urgency first, then engagement, then recency.
    static func pickStartWatching(from saved: [WatchShowItem]) -> WatchShowItem? {
        guard !saved.isEmpty else { return nil }
        return saved.max { lhs, rhs in startScore(lhs) < startScore(rhs) }
    }

    private static func startScore(_ show: WatchShowItem) -> Double {
        var s = 0.0
        if show.isNewEpisode == true { s += 1000 }
        if show.watchProgressState == .watching { s += 500 }
        if show.userReaction == "up" { s += 200 }
        s += min(300, show.trendScore * 2)
        let stamp = WatchMyListDisplay.savedDate(for: show).timeIntervalSince1970
        s += min(120, stamp / 1_000_000)
        return s
    }

    /// Saved shows with “urgent” surface cues (new ep, fresh release badge, this week).
    static func urgencySaved(from saved: [WatchShowItem], excludingIds: Set<String> = []) -> [WatchShowItem] {
        let rows = saved.filter { !excludingIds.contains($0.id) }
        return rows.filter { show in
            if show.isNewEpisode == true { return true }
            let b = (show.releaseBadge ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if b == "new" || b == "this_week" { return true }
            return false
        }.sorted { lhs, rhs in
            let ln = lhs.isNewEpisode == true ? 1 : 0
            let rn = rhs.isNewEpisode == true ? 1 : 0
            if ln != rn { return ln > rn }
            let lw = lhs.watchProgressState == .watching ? 1 : 0
            let rw = rhs.watchProgressState == .watching ? 1 : 0
            if lw != rw { return lw > rw }
            return WatchMyListDisplay.savedDate(for: lhs) > WatchMyListDisplay.savedDate(for: rhs)
        }
    }

    static func startWatchingReason(for show: WatchShowItem) -> String {
        if show.isNewEpisode == true { return "New episode available" }
        if show.watchProgressState == .watching { return "Pick up where you left off" }
        return "Ready to watch"
    }
}

// MARK: - Show card (grid / phone)


/// Compact “next action” hero for My List / habit loop.
struct WatchStartWatchingCard: View {
    let show: WatchShowItem
    let reason: String
    let onOpenProvider: () -> Void

    private var thumbW: CGFloat { DeviceLayout.isPad ? 100 : 88 }
    private var thumbH: CGFloat { DeviceLayout.isPad ? 142 : 124 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WatchShowPosterImage(
                show: show,
                width: thumbW,
                height: thumbH,
                cornerRadius: 12,
                continuousCornerStyle: true,
                showProgressWhenLoading: true,
                placeholderSymbolFont: .title3
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("Start Watching")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(show.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                if let p = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                    Label(p, systemImage: WatchProviderIcons.systemImage(for: p))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(reason)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button(action: onOpenProvider) {
                    let title = StreamingProviderCatalog.definition(
                        forPrimaryProvider: show.primaryProvider,
                        providers: show.providers
                    )?.primaryActionTitle ?? "Open to watch"
                    Text(title)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Card action row (Save / progress / reactions)

/// Shared horizontal actions for detail-style Watch cards (More Picks + New Episodes carousel).
struct WatchCardActionRow: View {
    let show: WatchShowItem
    let onCycleWatchProgress: () -> Void
    let onReaction: (String) -> Void
    let onToggleSaved: (Bool) -> Void
    let onCaughtUp: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WatchDesign.spaceXS) {
                WatchCardIconAction(
                    title: "Save",
                    systemImage: (show.saved ?? false) ? "bookmark.fill" : "bookmark",
                    isOn: show.saved ?? false,
                    action: { onToggleSaved(!(show.saved ?? false)) }
                )
                .accessibilityHint("Adds this show to your saved list.")

                WatchCardIconAction(
                    title: show.watchProgressState.shortTitle,
                    systemImage: show.watchProgressState.iconSystemName,
                    isOn: show.watchProgressState != .notStarted,
                    action: onCycleWatchProgress
                )
                .accessibilityHint("Cycles between not started, watching, and finished.")

                WatchCardIconAction(
                    title: "Like",
                    systemImage: show.userReaction == "up" ? "hand.thumbsup.fill" : "hand.thumbsup",
                    isOn: show.userReaction == "up",
                    action: { onReaction((show.userReaction == "up") ? "none" : "up") },
                    subtitle: numericSubtitle(show.upvotes)
                )
                .accessibilityHint("Helps personalize your recommendations.")

                WatchCardIconAction(
                    title: "Pass",
                    systemImage: show.userReaction == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                    isOn: show.userReaction == "down",
                    action: { onReaction((show.userReaction == "down") ? "none" : "down") },
                    subtitle: numericSubtitle(show.downvotes)
                )
                .accessibilityHint("Tells Watch to show fewer picks like this.")

                if show.saved == true, show.isNewEpisode == true {
                    WatchCardIconAction(
                        title: "Caught up",
                        systemImage: "checkmark.seal.fill",
                        isOn: false,
                        action: onCaughtUp
                    )
                    .accessibilityHint("Clears the new episode highlight for this saved show.")
                }
            }
        }
    }

    private func numericSubtitle(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return "\(n)"
    }
}

struct WatchShowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let show: WatchShowItem
    /// One trust-building recommendation line (no raw low match %).
    let recommendationReason: String
    /// Position in the visible grid (for optional “Trending” treatment on early rows).
    var listIndex: Int? = nil
    /// Same batch used for badge context (e.g. trending).
    var badgeBatch: [WatchShowItem] = []
    let onCycleWatchProgress: () -> Void
    let onReaction: (String) -> Void
    let onToggleSaved: (Bool) -> Void
    let onCaughtUp: () -> Void
    /// Long-press when `show.rankDebug != nil` (server gated).
    var onInspectRankDebug: (() -> Void)? = nil

    private var isPad: Bool { DeviceLayout.isPad }
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 104 : (isPad ? 92 : 72) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 146 : (isPad ? 128 : 104) }
    private var cardPadding: CGFloat { WatchDesign.spaceMD }
    private var cardCornerRadius: CGFloat { WatchDesign.radiusCardLarge }
    private var posterCornerRadius: CGFloat { WatchDesign.radiusBadge }

    private var metaFont: Font {
        WatchType.providerLine(isPad: isPad, isLargePad: DeviceLayout.isLargePad)
    }

    var body: some View {
        HStack(alignment: .top, spacing: WatchDesign.spaceSM) {
            WatchShowPosterImage(
                show: show,
                width: thumbWidth,
                height: thumbHeight,
                cornerRadius: posterCornerRadius,
                continuousCornerStyle: false,
                showProgressWhenLoading: true,
                placeholderSymbolFont: DeviceLayout.isLargePad ? .title3 : .callout
            )

            VStack(alignment: .leading, spacing: WatchDesign.spaceXS) {
                HStack(alignment: .firstTextBaseline, spacing: WatchDesign.spaceXS) {
                    Text(show.title)
                        .font(WatchType.detailCardTitle(isPad: isPad, dynamic: dynamicTypeSize))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    WatchListProgressBadge(state: show.watchProgressState)
                    if let kind = WatchBadgeFormatting.primaryBadge(for: show, listIndex: listIndex, in: badgeBatch) {
                        WatchBadge(kind: kind, compact: true, useSolidFill: false)
                    }
                }

                primaryProviderLine

                Text(recommendationReason)
                    .font(WatchType.reasonLine)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel("Recommendation. \(recommendationReason)")

                if !show.seasonEpisodeStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(show.seasonEpisodeStatus)
                        .font(DeviceLayout.isLargePad ? .caption.weight(.medium) : .caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(show.synopsis)
                    .font(DeviceLayout.isLargePad ? .subheadline : (isPad ? .caption : .caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                StreamingProviderLaunchControl(show: show, style: .cardCompact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, WatchDesign.spaceXS)

                WatchCardActionRow(
                    show: show,
                    onCycleWatchProgress: onCycleWatchProgress,
                    onReaction: onReaction,
                    onToggleSaved: onToggleSaved,
                    onCaughtUp: onCaughtUp
                )
                .padding(.top, WatchDesign.spaceXS)
            }
        }
        .padding(cardPadding)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.75).onEnded { _ in
                guard show.rankDebug != nil, onInspectRankDebug != nil else { return }
                onInspectRankDebug?()
            }
        )
    }

    @ViewBuilder
    private var primaryProviderLine: some View {
        if let primary = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: WatchDesign.spaceXS) {
                Image(systemName: WatchProviderIcons.systemImage(for: primary))
                    .font(metaFont)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(metaFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Streaming on \(primary)")
        } else if let first = show.providers.first {
            HStack(alignment: .firstTextBaseline, spacing: WatchDesign.spaceXS) {
                Image(systemName: WatchProviderIcons.systemImage(for: first))
                    .font(metaFont)
                    .foregroundStyle(.secondary)
                Text(first)
                    .font(metaFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Streaming on \(first)")
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

// MARK: - Design-doc aliases (same types, clearer names in docs / previews)
typealias WatchCardView = WatchShowCard
typealias WatchDetailCard = WatchShowCard
typealias PlaceholderPosterView = WatchPremiumPosterPlaceholder
typealias WatchActionButton = WatchCardIconAction
typealias WatchBadgeChip = WatchBadgeView
typealias BadgeView = WatchBadgeView

// MARK: - Loading skeleton

struct WatchCardSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 112 : (DeviceLayout.isPad ? 96 : 72) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 156 : (DeviceLayout.isPad ? 132 : 104) }
    private var cardPadding: CGFloat { WatchDesign.spaceMD }
    private var cornerRadius: CGFloat { WatchDesign.radiusCardLarge }

    var body: some View {
        HStack(alignment: .top, spacing: WatchDesign.spaceSM) {
            RoundedRectangle(cornerRadius: WatchDesign.radiusBadge)
                .fill(Color(.secondarySystemFill))
                .frame(width: thumbWidth, height: thumbHeight)
            VStack(alignment: .leading, spacing: WatchDesign.spaceXS) {
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

#if DEBUG
extension WatchShowItem {
    /// Preview-only fixture (no trusted poster; uses premium placeholder).
    static var watchPreviewSample: WatchShowItem {
        WatchShowItem(
            id: "watch-preview-1",
            title: "Reacher",
            posterURL: "",
            posterStatus: "missing",
            posterTrusted: nil,
            posterMissing: nil,
            posterConfidence: nil,
            posterResolution: nil,
            posterResolutionSource: nil,
            posterMatchDebug: nil,
            synopsis: "Jack Reacher roams the country taking odd jobs and solving problems with direct action.",
            providers: ["Amazon Prime Video"],
            primaryProvider: "Amazon Prime Video",
            genres: ["Thriller", "Crime"],
            primaryGenre: "Thriller",
            releaseDate: "2024-01-01",
            lastEpisodeAirDate: nil,
            nextEpisodeAirDate: nil,
            releaseBadge: "new",
            releaseBadgeLabel: "Recently aired",
            seasonEpisodeStatus: "Season 2 · 3 episodes left",
            trendScore: 88,
            rankScore: nil,
            seen: false,
            watchState: "watching",
            saved: true,
            savedAtUTC: nil,
            isNewEpisode: true,
            isUpcomingRelease: false,
            caughtUpReleaseDate: nil,
            userReaction: nil,
            rankOrder: nil,
            recommendationReason: nil,
            rankDebug: nil,
            upvotes: 12,
            downvotes: 1,
            homeFeedSection: nil
        )
    }
}

#Preview("Watch card — dark") {
    WatchShowCard(
        show: .watchPreviewSample,
        recommendationReason: WatchCardRecommendation.listReasonLine(
            for: .watchPreviewSample,
            listIndex: 0,
            rankingBatch: [.watchPreviewSample],
            badgeBatch: [.watchPreviewSample]
        ),
        listIndex: 0,
        badgeBatch: [.watchPreviewSample],
        onCycleWatchProgress: { },
        onReaction: { _ in },
        onToggleSaved: { _ in },
        onCaughtUp: {}
    )
    .padding()
    .background(AppTheme.watchScreenBackground(for: .dark))
    .preferredColorScheme(.dark)
}

#Preview("New episodes carousel") {
    VStack(alignment: .leading, spacing: 10) {
        WatchSectionHeader(title: "New Episodes for You")
        WatchNewEpisodesCarousel(
            items: [.watchPreviewSample],
            rankingBatch: [.watchPreviewSample],
            onToggleSaved: { _, _ in },
            onSelect: { _ in },
            onCycleWatchProgress: { _ in },
            onReaction: { _, _ in },
            onCaughtUp: { _ in }
        )
    }
    .padding()
    .background(AppTheme.watchScreenBackground(for: .dark))
    .preferredColorScheme(.dark)
}
#endif
