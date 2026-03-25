import SwiftUI

// MARK: - Tonight’s Pick hero
//
// Design intent (decision speed + premium feel):
// - Full-bleed poster + top→bottom gradient keeps the eye on *one* focal object and answers “what tonight?” in a glance.
// - Label → badge → title → provider → actions follows a single visual path (F-pattern), reducing scan time vs. a dense list row.
// - Primary “Watch Now” + secondary “Save” stay separated from the poster tap target so navigation and streaming actions don’t conflict.
//
// Accessibility:
// - High-contrast white typography on darkened gradient; no reliance on color alone for the badge (copy says “New Episode” / “New”).
// - Dynamic Type: title wraps with line limits; hero min-height grows at accessibility sizes; buttons use large control size.
// - `accessibilityLabel`/`Hint` on the card button and provider row where helpful (badge copy uses “Recently aired” when the API marks a recent episode).
//
// Performance:
// - One `AsyncImage`, one `LinearGradient`, one shadow; no blur/backdrop filters.
//
// Badges use `release_badge` codes from the API (`new` = recently aired episode window), not label text alone.

// MARK: - Model

/// Display-only input for `HeroWatchCardView` (testable, preview-friendly).
struct HeroWatchCardModel: Equatable {
    var title: String
    var subtitle: String?
    var imageURL: URL?
    var providerName: String
    /// SF Symbol name for the provider row (e.g. `play.rectangle.fill`).
    var providerIconSystemName: String
    var isNewEpisode: Bool
    /// `release_badge == "new"` (recently aired; distinct from personalized new-episode flag).
    var isNew: Bool
    /// Short label from `release_badge_label` (e.g. “Recently aired”).
    var badgeLabel: String?
    var isSaved: Bool
    /// Matches `StreamingProviderDefinition.primaryActionTitle` when the provider is in the catalog (e.g. “Open in Netflix”).
    var primaryLaunchTitle: String

    init(
        title: String,
        subtitle: String?,
        imageURL: URL?,
        providerName: String,
        providerIconSystemName: String,
        isNewEpisode: Bool,
        isNew: Bool,
        badgeLabel: String? = nil,
        isSaved: Bool = false,
        primaryLaunchTitle: String = "Watch Now"
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.providerName = providerName
        self.providerIconSystemName = providerIconSystemName
        self.isNewEpisode = isNewEpisode
        self.isNew = isNew
        self.badgeLabel = badgeLabel
        self.isSaved = isSaved
        self.primaryLaunchTitle = primaryLaunchTitle
    }
}

extension HeroWatchCardModel {
    /// Maps existing API model into hero content.
    init(show: WatchShowItem) {
        title = show.title
        let trimmedPrimary = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName: String = {
            if !trimmedPrimary.isEmpty { return trimmedPrimary }
            if let first = show.providers.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
                return first
            }
            return "Streaming"
        }()
        providerName = resolvedName
        providerIconSystemName = WatchProviderIcons.systemImage(for: resolvedName)
        imageURL = URL(string: show.posterURL)

        isNewEpisode = show.isNewEpisode == true
        isSaved = show.saved == true
        badgeLabel = show.releaseBadgeLabel
        if let code = show.releaseBadge?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            isNew = (code == "new")
        } else {
            isNew = false
        }

        let status = show.seasonEpisodeStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty {
            subtitle = status
        } else if isNewEpisode {
            subtitle = "Recently aired"
        } else {
            let syn = show.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
            if syn.isEmpty {
                subtitle = nil
            } else if syn.count > 90 {
                subtitle = String(syn.prefix(87)) + "…"
            } else {
                subtitle = syn
            }
        }

        if let def = StreamingProviderCatalog.definition(
            forPrimaryProvider: show.primaryProvider,
            providers: show.providers
        ) {
            primaryLaunchTitle = def.primaryActionTitle
        } else {
            primaryLaunchTitle = "Watch Now"
        }
    }
}

// MARK: - Hero card

/// Featured “Tonight’s Pick” treatment: full-bleed art, gradient, clear hierarchy, primary/secondary actions.
struct HeroWatchCardView: View {
    let model: HeroWatchCardModel
    var onPrimaryAction: () -> Void
    var onSecondaryAction: () -> Void
    /// Opens detail / selection when the main art + text region is tapped (buttons are separate).
    var onCardTap: (() -> Void)?
    /// Subtle “Tonight Mode” ring + glow (local evening hours only).
    var tonightEmphasis: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var cornerRadius: CGFloat { DeviceLayout.isLargePad ? 20 : 18 }
    private var maxCardWidth: CGFloat? {
        guard DeviceLayout.isPad,
              DeviceLayout.useRegularWidthTabletLayout(horizontalSizeClass: horizontalSizeClass) else {
            return nil
        }
        return min(720, DeviceLayout.contentMaxWidth)
    }

    var body: some View {
        content
            .frame(maxWidth: maxCardWidth ?? .infinity)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            mainTappableRegion
            actionRow
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.22), lineWidth: 1)
        )
        .overlay {
            if tonightEmphasis {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.62, green: 0.42, blue: 0.95).opacity(0.95),
                                Color(red: 0.98, green: 0.62, blue: 0.35).opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.14),
            radius: colorScheme == .dark ? 20 : 16,
            x: 0,
            y: 8
        )
        .shadow(
            color: tonightEmphasis ? Color(red: 0.55, green: 0.35, blue: 0.9).opacity(colorScheme == .dark ? 0.45 : 0.28) : .clear,
            radius: tonightEmphasis ? 18 : 0,
            x: 0,
            y: 8
        )
        .accessibilityElement(children: .contain)
    }

    /// Poster + gradient + chrome; optionally wrapped in a plain button for “open detail”.
    @ViewBuilder
    private var mainTappableRegion: some View {
        let stack = heroStack
        if let onCardTap {
            Button(action: onCardTap) {
                stack
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tonight’s pick, \(model.title)")
            .accessibilityHint("Shows more about this title.")
        } else {
            stack
        }
    }

    private var heroStack: some View {
        ZStack(alignment: .bottomLeading) {
            posterAndGradient
            contentOverlay
        }
        .frame(minHeight: minHeroHeight)
        .clipped()
    }

    private var minHeroHeight: CGFloat {
        if dynamicTypeSize >= .accessibility3 {
            return 400
        }
        if dynamicTypeSize >= .accessibility1 {
            return 340
        }
        return 300
    }

    private var posterAndGradient: some View {
        ZStack {
            posterLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var posterLayer: some View {
        if let url = model.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholderPoster(showProgress: true)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderPoster(showProgress: false)
                @unknown default:
                    placeholderPoster(showProgress: false)
                }
            }
        } else {
            placeholderPoster(showProgress: false)
        }
    }

    private func placeholderPoster(showProgress: Bool) -> some View {
        ZStack {
            Rectangle().fill(Color(.secondarySystemFill))
            if showProgress {
                ProgressView()
            } else {
                Image(systemName: "tv.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gradientColors: [Color] {
        let top = Color.black.opacity(colorScheme == .dark ? 0.35 : 0.25)
        let mid = Color.black.opacity(colorScheme == .dark ? 0.5 : 0.45)
        let bottom = Color.black.opacity(colorScheme == .dark ? 0.82 : 0.78)
        return [top, mid, bottom]
    }

    private var contentOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Tonight’s pick")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                heroBadge
            }

            Spacer(minLength: 12)

            Text(model.title)
                .font(.title.bold())
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 5 : 3)
                .minimumScaleFactor(0.85)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)

            if let sub = model.subtitle, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(sub)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .padding(.top, 6)
            }

            providerRow
                .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var heroBadge: some View {
        if model.isNewEpisode {
            Text(model.badgeLabel ?? "Recently aired")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.green.opacity(0.92)))
                .foregroundStyle(.white)
                .accessibilityLabel(model.badgeLabel ?? "Recently aired")
        } else if model.isNew {
            Text(model.badgeLabel ?? "Recently aired")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange.opacity(0.92)))
                .foregroundStyle(.white)
                .accessibilityLabel(model.badgeLabel ?? "Recently aired")
        }
    }

    private var providerRow: some View {
        Label {
            Text(model.providerName)
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: model.providerIconSystemName)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .lineLimit(2)
        .accessibilityLabel("Streaming on \(model.providerName)")
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                AppHaptics.lightImpact()
                onPrimaryAction()
            } label: {
                Label {
                    Text(model.primaryLaunchTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                } icon: {
                    Image(systemName: "play.fill")
                }
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            // Use accent tint — `.tint(.white)` on borderedProminent fills the pill white *and* keeps label white → invisible text.
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .controlSize(.large)
            .accessibilityLabel(model.primaryLaunchTitle)

            Button {
                AppHaptics.selection()
                onSecondaryAction()
            } label: {
                Label(model.isSaved ? "Saved" : "Save", systemImage: model.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .foregroundStyle(Color.white)
            .controlSize(.large)
            .accessibilityLabel(model.isSaved ? "Saved" : "Save to list")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.55 : 0.5))
        )
    }

}

// MARK: - Dynamic Type helper

private extension DynamicTypeSize {
    var isAccessibilitySize: Bool {
        self >= .accessibility1
    }
}

// MARK: - Previews

#Preview("Hero — light") {
    ScrollView {
        HeroWatchCardView(
            model: HeroWatchCardModel(
                title: "The Last Lighthouse",
                subtitle: "Season 2 · Recently aired",
                imageURL: URL(string: "https://picsum.photos/800/1200"),
                providerName: "HBO Max",
                providerIconSystemName: "tv.fill",
                isNewEpisode: true,
                isNew: false,
                isSaved: false,
                primaryLaunchTitle: "Open in HBO Max"
            ),
            onPrimaryAction: {},
            onSecondaryAction: {},
            onCardTap: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hero — dark") {
    ScrollView {
        HeroWatchCardView(
            model: HeroWatchCardModel(
                title: "Short Title",
                subtitle: nil,
                imageURL: nil,
                providerName: "Netflix",
                providerIconSystemName: "play.rectangle.fill",
                isNewEpisode: false,
                isNew: true,
                isSaved: true,
                primaryLaunchTitle: "Open in Netflix"
            ),
            onPrimaryAction: {},
            onSecondaryAction: {},
            onCardTap: nil
        )
        .padding()
    }
    .preferredColorScheme(.dark)
    .background(Color.black)
}
