import SwiftUI

// MARK: - Design system

private enum OnboardingUX {
    static let cardCorner: CGFloat = 20
    static let rowCorner: CGFloat = 14
    static let searchCorner: CGFloat = 14
    static let blockSpacing: CGFloat = 22
    static let innerSpacing: CGFloat = 12
    static let gridGap: CGFloat = 12
    static let rowMinHeight: CGFloat = 56
    static let spotlightWidth: CGFloat = 156
    static let spotlightHeight: CGFloat = 128
}

// MARK: - Labels (word-friendly wrapping, no tight hyphenation)

private struct CardTitleText: View {
    let text: String
    let size: Font

    var body: some View {
        Text(text)
            .font(size)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.88)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RowTitleText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Genre / streaming — choice cards (2×N grid, generous cells)

/// Premium multi-select card: icon in soft circle, title, checkmark affordance when selected.
struct OnboardingChoiceCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            AppHaptics.selection()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: systemImage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    }
                    CardTitleText(
                        text: title,
                        size: .subheadline.weight(isSelected ? .semibold : .medium)
                    )
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: OnboardingUX.cardCorner, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: OnboardingUX.cardCorner, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.clear
                                : Color(.separator).opacity(colorScheme == .dark ? 0.45 : 0.32),
                            lineWidth: 1
                        )
                }
                .shadow(color: isSelected ? Color.accentColor.opacity(0.38) : .clear, radius: 14, y: 6)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? Color.white : Color.secondary,
                        isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.35)
                    )
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum OnboardingGenreVisual {
    static func icon(for genre: String) -> String {
        switch genre {
        case "Action": return "flame.fill"
        case "Drama": return "theatermasks.fill"
        case "Comedy": return "face.smiling.fill"
        case "Sci-Fi": return "sparkles"
        case "Documentary": return "doc.text.fill"
        case "Reality": return "person.3.fill"
        case "Crime": return "magnifyingglass.circle.fill"
        case "Animation": return "paintbrush.fill"
        case "Thriller": return "moon.stars.fill"
        case "Horror": return "bolt.fill"
        case "Fantasy": return "wand.and.stars"
        case "Romance": return "heart.fill"
        default: return "film.fill"
        }
    }
}

struct OnboardingGenreCardGrid: View {
    let genres: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let n = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: OnboardingUX.gridGap), count: n)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: OnboardingUX.gridGap) {
            ForEach(genres, id: \.self) { genre in
                OnboardingChoiceCard(
                    title: genre,
                    systemImage: OnboardingGenreVisual.icon(for: genre),
                    isSelected: isSelected(genre)
                ) {
                    toggle(genre)
                }
                .aspectRatio(0.92, contentMode: .fill)
            }
        }
    }
}

struct OnboardingStreamingCardGrid: View {
    let providers: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let n = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: OnboardingUX.gridGap), count: n)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: OnboardingUX.gridGap) {
            ForEach(providers, id: \.self) { name in
                OnboardingChoiceCard(
                    title: name,
                    systemImage: "play.rectangle.fill",
                    isSelected: isSelected(name)
                ) {
                    toggle(name)
                }
                .aspectRatio(0.92, contentMode: .fill)
            }
        }
    }
}

// MARK: - Shared search field

private struct OnboardingSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body.weight(.medium))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: OnboardingUX.searchCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingUX.searchCorner, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.22), lineWidth: 1)
        }
    }
}

// MARK: - League spotlight (horizontal “deck”, not chips)

private enum LeagueSpotlightVisual {
    static func icon(for key: String) -> String {
        switch key {
        case "NFL": return "football.fill"
        case "NBA", "WNBA", "NCAAB": return "basketball.fill"
        case "MLB": return "baseball.fill"
        case "NHL": return "sportscourt.fill"
        case "MLS", "Premier League", "Champions League": return "soccerball"
        case "NCAAF": return "football.fill"
        case "UFC": return "figure.boxing"
        case "PGA", "ATP", "WTA": return "figure.tennis"
        case "Formula 1": return "flag.checkered"
        case "NASCAR": return "car.side.fill"
        default: return "sportscourt.fill"
        }
    }
}

private struct LeagueSpotlightCard: View {
    let leagueKey: String
    let displayTitle: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            AppHaptics.lightImpact()
            action()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: LeagueSpotlightVisual.icon(for: leagueKey))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .padding(.bottom, 10)
                Spacer(minLength: 0)
                CardTitleText(text: displayTitle, size: .footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: OnboardingUX.spotlightWidth, height: OnboardingUX.spotlightHeight, alignment: .topLeading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color(.separator).opacity(colorScheme == .dark ? 0.4 : 0.28),
                        lineWidth: 1
                    )
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Selectable list row (leagues & teams — consistent, scalable)

struct OnboardingSelectableRow: View {
    let title: String
    var secondary: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            AppHaptics.selection()
            action()
        }) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    RowTitleText(text: title)
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color.secondary,
                        isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.3)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: OnboardingUX.rowMinHeight)
            .background {
                RoundedRectangle(cornerRadius: OnboardingUX.rowCorner, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12) : Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: OnboardingUX.rowCorner, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color(.separator).opacity(0.22),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - League onboarding (carousel + categories + search, not a chip grid)

struct LeagueOnboardingSelectionView: View {
    let leagues: [String]
    let featuredLeagues: [String]
    let categories: [(name: String, keys: [String])]
    let displayTitle: (String) -> String
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    @State private var query = ""

    private var q: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredAll: [String] {
        guard !q.isEmpty else { return leagues }
        return leagues.filter { displayTitle($0).localizedCaseInsensitiveContains(q) }
    }

    private var spotlightKeys: [String] {
        featuredLeagues.filter { leagues.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingUX.blockSpacing) {
            OnboardingSearchField(placeholder: "Search every league", text: $query)

            if q.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Start here")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OnboardingUX.innerSpacing) {
                            ForEach(spotlightKeys, id: \.self) { key in
                                LeagueSpotlightCard(
                                    leagueKey: key,
                                    displayTitle: displayTitle(key),
                                    isSelected: isSelected(key)
                                ) {
                                    toggle(key)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                VStack(alignment: .leading, spacing: OnboardingUX.blockSpacing) {
                    ForEach(categories, id: \.name) { cat in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(cat.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            VStack(spacing: 10) {
                                ForEach(cat.keys, id: \.self) { key in
                                    OnboardingSelectableRow(
                                        title: displayTitle(key),
                                        secondary: nil,
                                        isSelected: isSelected(key)
                                    ) {
                                        toggle(key)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Results")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if filteredAll.isEmpty {
                        Text("No leagues match “\(q)”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredAll, id: \.self) { key in
                                OnboardingSelectableRow(
                                    title: displayTitle(key),
                                    secondary: nil,
                                    isSelected: isSelected(key)
                                ) {
                                    toggle(key)
                                }
                            }
                        }
                    }
                }
            }

            Label("Prefer league-level only? Skip the next screen — or pick teams in Sports anytime.", systemImage: "hand.wave.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Team onboarding (list rows inside groups, not uneven grids)

struct TeamOnboardingSelectionView: View {
    let leagues: [String]
    let teamsForLeague: (String) -> [String]
    let displayTitle: (String) -> String
    let isTeamSelected: (String) -> Bool
    let toggleTeam: (String) -> Void
    let selectedCountInLeague: (String) -> Int

    @Environment(\.onboardingScrollProxy) private var scrollProxy

    @State private var query = ""
    @State private var expandedLeagues: Set<String> = []

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesQuery(_ team: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        return team.localizedCaseInsensitiveContains(normalizedQuery)
    }

    private var leaguesWithMatches: [String] {
        if normalizedQuery.isEmpty { return leagues }
        return leagues.filter { league in
            teamsForLeague(league).contains(where: { matchesQuery($0) })
        }
    }

    private func isLeagueExpanded(_ league: String) -> Bool {
        if !normalizedQuery.isEmpty { return true }
        return expandedLeagues.contains(league)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingUX.blockSpacing) {
            OnboardingSearchField(placeholder: "Search teams & clubs", text: $query)

            if normalizedQuery.isEmpty {
                Text("Jump to a league")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(leagues, id: \.self) { league in
                            Button {
                                AppHaptics.lightImpact()
                                expandedLeagues.insert(league)
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    scrollProxy?.scrollTo(league, anchor: .top)
                                }
                            } label: {
                                Text(displayTitle(league))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background {
                                        Capsule()
                                            .fill(Color(.secondarySystemGroupedBackground))
                                    }
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(leaguesWithMatches, id: \.self) { league in
                    TeamLeagueGroupSection(
                        title: displayTitle(league),
                        isExpanded: isLeagueExpanded(league),
                        onToggle: {
                            if normalizedQuery.isEmpty {
                                if expandedLeagues.contains(league) {
                                    expandedLeagues.remove(league)
                                } else {
                                    expandedLeagues.insert(league)
                                }
                            }
                        },
                        selectedCount: selectedCountInLeague(league)
                    ) {
                        let teams = teamsForLeague(league).filter { matchesQuery($0) }
                        VStack(spacing: 8) {
                            ForEach(teams, id: \.self) { team in
                                OnboardingSelectableRow(
                                    title: team,
                                    secondary: nil,
                                    isSelected: isTeamSelected(team)
                                ) {
                                    toggleTeam(team)
                                }
                            }
                        }
                    }
                    .id(league)
                }
            }
            .onChange(of: query) { _ in
                let nq = normalizedQuery
                if !nq.isEmpty, let first = leaguesWithMatches.first {
                    withAnimation {
                        scrollProxy?.scrollTo(first, anchor: .top)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Can’t find someone? Try search — we add names over time. League picks still personalize your feed.", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Label("Pick none, some, or many — edit anytime in Sports.", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Team league group (accordion)

struct TeamLeagueGroupSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let selectedCount: Int
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                AppHaptics.selection()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    onToggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if selectedCount > 0 {
                            Text("\(selectedCount) selected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, 12)
                    .padding(.leading, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Live TV for sports (single-select, matches Settings → Customize)

/// Single-select list for `SportsProviderPreferences` — used in personalization onboarding.
struct OnboardingSportsTVProviderList: View {
    @Binding var selectedKey: String
    let options: [(key: String, label: String)]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(options, id: \.key) { option in
                let isOn = selectedKey == option.key
                Button {
                    AppHaptics.selection()
                    selectedKey = option.key
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label)
                                .font(.body.weight(isOn ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if option.key != SportsProviderPreferences.allProviderKey {
                                Text("We’ll prioritize games airing on networks your plan typically carries.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Show every game we know about; you can narrow this later in Sports → Customize.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isOn ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color(.secondarySystemGroupedBackground))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isOn ? Color.accentColor.opacity(0.45) : Color(.separator).opacity(colorScheme == .dark ? 0.35 : 0.22),
                                lineWidth: isOn ? 1.5 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
