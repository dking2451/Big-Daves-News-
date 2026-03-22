import SwiftUI

// MARK: - Preferences (ObservableObject)

/// Central filter state for the Watch tab. Instant updates: bindings drive `filteredShows` immediately;
/// `refresh()` runs only when `onlySaved` API mode changes (My List chip).
@MainActor
final class WatchFilterPreferences: ObservableObject {
    @Published var listScope: WatchListScope = .all
    /// When `true`, include titles already marked seen in the main feed (API `hideSeen: false`).
    @Published var showWatched = false
    /// Provider display names; empty = no provider filter (all).
    @Published var selectedProviders: Set<String> = []
    /// Genre tokens: content names plus `New Episodes` and `My List`. Empty = no extra genre filters.
    @Published var selectedGenres: Set<String> = []
    @Published var myListSort: String = "New Episodes"
    @Published var advancedExpanded = false
    /// When true, a show must match on **primary** provider if it intersects selected providers.
    @Published var matchPrimaryProviderOnly = false

    var onlySavedAPI: Bool {
        selectedGenres.contains("My List")
    }

    func reset() {
        listScope = .all
        showWatched = false
        selectedProviders = []
        selectedGenres = []
        myListSort = "New Episodes"
        advancedExpanded = false
        matchPrimaryProviderOnly = false
    }

    var hasNonDefaultFilters: Bool {
        listScope != .all
            || showWatched
            || !selectedProviders.isEmpty
            || !selectedGenres.isEmpty
            || myListSort != "New Episodes"
            || matchPrimaryProviderOnly
    }
}

// MARK: - Reusable chip

struct FilterChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color(.separator).opacity(0.55),
                        lineWidth: 1
                    )
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

// MARK: - Section header (optional chrome)

struct WatchFilterSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

// MARK: - Sheet

struct WatchFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var filterPrefs: WatchFilterPreferences

    let providerOptions: [String]
    let genreOptions: [String]
    let myListSortOptions: [String]

    private let chipSpacing: CGFloat = 10

    var body: some View {
        NavigationStack {
            Form {
                myShowsSection
                providersSection
                genresSection
                if filterPrefs.selectedGenres.contains("My List") {
                    myListSortSection
                }
                advancedSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterPrefs.reset()
                        }
                    }
                    .fontWeight(.medium)
                    .disabled(!filterPrefs.hasNonDefaultFilters)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var myShowsSection: some View {
        Section {
            Picker("My shows", selection: $filterPrefs.listScope) {
                ForEach(WatchListScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

        } header: {
            WatchFilterSectionHeader(title: "My shows", subtitle: "Which titles to start from")
        } footer: {
            Text(filterPrefs.listScope.detailFooter)
                .font(.footnote)
        }
    }

    private var providersSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: chipSpacing) {
                    FilterChip(
                        title: "All",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: filterPrefs.selectedProviders.isEmpty
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterPrefs.selectedProviders = []
                        }
                    }
                    ForEach(providerOptions, id: \.self) { name in
                        FilterChip(
                            title: name,
                            systemImage: WatchFilterIcons.providerIcon(for: name),
                            isSelected: filterPrefs.selectedProviders.contains(name)
                        ) {
                            toggleProvider(name)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            WatchFilterSectionHeader(
                title: "Providers",
                subtitle: "Pick one or more, or All for every service"
            )
        }
    }

    private func toggleProvider(_ name: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if filterPrefs.selectedProviders.contains(name) {
                filterPrefs.selectedProviders.remove(name)
            } else {
                filterPrefs.selectedProviders.insert(name)
            }
        }
    }

    private var genresSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: chipSpacing) {
                    FilterChip(
                        title: "All",
                        systemImage: "square.grid.2x2",
                        isSelected: filterPrefs.selectedGenres.isEmpty
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterPrefs.selectedGenres = []
                        }
                    }
                    FilterChip(
                        title: "New Episodes",
                        systemImage: "sparkles.tv.fill",
                        isSelected: filterPrefs.selectedGenres.contains("New Episodes")
                    ) {
                        toggleGenre("New Episodes")
                    }
                    FilterChip(
                        title: "My List",
                        systemImage: "bookmark.fill",
                        isSelected: filterPrefs.selectedGenres.contains("My List")
                    ) {
                        toggleGenre("My List")
                    }
                    ForEach(genreOptions, id: \.self) { name in
                        FilterChip(
                            title: name,
                            systemImage: WatchFilterIcons.genreIcon(for: name),
                            isSelected: filterPrefs.selectedGenres.contains(name)
                        ) {
                            toggleGenre(name)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            WatchFilterSectionHeader(
                title: "Genres & lists",
                subtitle: "Combine chips — e.g. My List + Drama"
            )
        }
    }

    private func toggleGenre(_ name: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if filterPrefs.selectedGenres.contains(name) {
                filterPrefs.selectedGenres.remove(name)
            } else {
                filterPrefs.selectedGenres.insert(name)
            }
        }
    }

    private var myListSortSection: some View {
        Section {
            Picker("Sort My List", selection: $filterPrefs.myListSort) {
                ForEach(myListSortOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Sort My List")
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $filterPrefs.advancedExpanded) {
                Toggle("Hide watched", isOn: Binding(
                    get: { !filterPrefs.showWatched },
                    set: { filterPrefs.showWatched = !$0 }
                ))
                .disabled(filterPrefs.listScope != .all)
                .opacity(filterPrefs.listScope == .all ? 1 : 0.45)

                Toggle("Only titles on selected providers (primary)", isOn: $filterPrefs.matchPrimaryProviderOnly)
                    .disabled(filterPrefs.selectedProviders.isEmpty)
            } label: {
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .font(.body.weight(.medium))
            }
        } footer: {
            Text("Hide watched applies when My shows is set to All. Primary match narrows to the show’s main streaming service when you pick providers above.")
                .font(.footnote)
        }
    }
}
