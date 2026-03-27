import SwiftUI

// MARK: - Sort (My List)

enum WatchMyListSortMode: String, CaseIterable, Identifiable {
    case recentlySaved = "Recently Saved"
    case newEpisodes = "New Episodes"
    case readyToWatch = "Ready to Watch"

    var id: String { rawValue }
}

/// Phase 1 **My List**: full-screen saved TV titles (Phase 2 embeds as a hub section).
struct WatchMyListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// iPad split: full-screen cover shows Done.
    var showsDismissButton: Bool = false

    @State private var shows: [WatchShowItem] = []
    @State private var sortMode: WatchMyListSortMode = .recentlySaved
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let deviceID = WatchDeviceIdentity.current

    private var padH: CGFloat { DeviceLayout.horizontalPadding }
    private var contentMaxWidth: CGFloat { DeviceLayout.contentMaxWidth }

    private var displayedShows: [WatchShowItem] {
        switch sortMode {
        case .recentlySaved:
            return shows.sorted { savedDate(for: $0) > savedDate(for: $1) }
        case .newEpisodes:
            return shows
                .filter { $0.isNewEpisode == true }
                .sorted { savedDate(for: $0) > savedDate(for: $1) }
        case .readyToWatch:
            return shows
                .filter { $0.seen != true }
                .sorted { $0.trendScore > $1.trendScore }
        }
    }

    var body: some View {
        Group {
            if isLoading && shows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                        headerCopyBlock
                        ForEach(0..<5, id: \.self) { _ in
                            WatchCardSkeleton()
                        }
                    }
                    .padding(.horizontal, padH)
                    .padding(.top, 8)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .redacted(reason: .placeholder)
            } else if let errorMessage, shows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                        headerCopyBlock
                        AppContentStateCard(
                            kind: .error,
                            systemImage: "wifi.exclamationmark",
                            title: "Couldn’t load My List",
                            message: errorMessage,
                            retryTitle: "Try again",
                            onRetry: { Task { await load() } },
                            isRetryDisabled: isLoading,
                            compact: false
                        )
                    }
                    .padding(.horizontal, padH)
                    .padding(.top, 8)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if shows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                        headerCopyBlock
                        myListEmptyState
                    }
                    .padding(.horizontal, padH)
                    .padding(.top, 8)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                        headerCopyBlock

                        if displayedShows.isEmpty {
                            AppContentStateCard(
                                kind: .empty,
                                systemImage: "line.3.horizontal.decrease.circle",
                                title: "Nothing matches this sort",
                                message: sortEmptyHint,
                                retryTitle: nil,
                                onRetry: nil,
                                compact: false
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(displayedShows.enumerated()), id: \.element.id) { index, show in
                                    WatchMyListShowRow(
                                        show: show,
                                        badgeBatch: displayedShows,
                                        listIndex: index,
                                        onRemoveFromSaved: {
                                            Task { await removeSaved(show) }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, padH)
                    .padding(.vertical, 10)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .refreshable { await load() }
            }
        }
        .background(AppTheme.watchScreenBackground(for: colorScheme))
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsDismissButton {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityHint("Closes My List.")
                }
                Menu {
                    Picker("Sort My List", selection: $sortMode) {
                        ForEach(WatchMyListSortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort My List")
                .disabled(shows.isEmpty)
            }
        }
        .task {
            await load()
        }
    }

    private var headerCopyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your saved watch list")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Subtitle. Your saved watch list")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var myListEmptyState: some View {
        BrandCard {
            VStack(alignment: .center, spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 40, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.primary.opacity(colorScheme == .dark ? 0.95 : 0.88))
                    .accessibilityHidden(true)

                Text("Nothing here yet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Save shows to build your watch list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    AppHaptics.selection()
                    dismiss()
                } label: {
                    Text("Browse Shows")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .accessibilityHint("Returns to Watch recommendations.")
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing here yet. Save shows to build your watch list. Browse Shows.")
    }

    private var sortEmptyHint: String {
        switch sortMode {
        case .recentlySaved:
            return "Try pulling to refresh."
        case .newEpisodes:
            return "No saved shows have a new episode badge right now. Try Recently Saved."
        case .readyToWatch:
            return "All saved shows are marked seen, or try another sort."
        }
    }

    private func savedDate(for show: WatchShowItem) -> Date {
        let raw = show.savedAtUTC?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return .distantPast }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw) ?? .distantPast
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let items = try await APIClient.shared.fetchWatchShows(
                limit: 50,
                minimumCount: 10,
                deviceID: deviceID,
                hideSeen: false,
                onlySaved: true
            )
            shows = items
        } catch {
            errorMessage = error.localizedDescription
            shows = []
        }
    }

    private func removeSaved(_ show: WatchShowItem) async {
        do {
            try await APIClient.shared.setWatchSaved(deviceID: deviceID, showID: show.id, saved: false)
            AppHaptics.selection()
            shows.removeAll { $0.id == show.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row (reusable card for My List; Phase 2 hub can share)

struct WatchMyListShowRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let show: WatchShowItem
    var badgeBatch: [WatchShowItem]
    var listIndex: Int
    let onRemoveFromSaved: () -> Void

    private var isPad: Bool { DeviceLayout.isPad }
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 88 : (isPad ? 76 : 64) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 124 : (isPad ? 108 : 92) }
    private var cornerRadius: CGFloat { DeviceLayout.isLargePad ? 18 : (isPad ? 16 : 14) }
    private var metaFont: Font {
        if DeviceLayout.isLargePad { return .subheadline.weight(.semibold) }
        if isPad { return .caption.weight(.semibold) }
        return .caption2.weight(.semibold)
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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(show.title)
                        .font(isPad ? .title3.weight(.semibold) : .headline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let kind = WatchBadgeFormatting.primaryBadge(for: show, listIndex: listIndex, in: badgeBatch) {
                        WatchBadgeView(kind: kind, compact: true, useSolidFill: false)
                    }
                }

                primaryProviderLine

                if !show.seasonEpisodeStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(show.seasonEpisodeStatus)
                        .font(DeviceLayout.isLargePad ? .caption.weight(.medium) : .caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                StreamingProviderLaunchControl(show: show, style: .cardCompact)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DeviceLayout.isLargePad ? 14 : (isPad ? 12 : 10))
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Remove from My List", role: .destructive) {
                onRemoveFromSaved()
            }
        }
    }

    @ViewBuilder
    private var primaryProviderLine: some View {
        if let primary = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: WatchProviderIcons.systemImage(for: primary))
                    .font(metaFont)
                    .foregroundStyle(AppTheme.watchSecondaryAccent.opacity(colorScheme == .dark ? 0.95 : 0.85))
                Text(primary)
                    .font(metaFont)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Primary provider: \(primary)")
        } else if let first = show.providers.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: WatchProviderIcons.systemImage(for: first))
                    .font(metaFont)
                Text(first)
                    .font(metaFont)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .accessibilityLabel("Provider: \(first)")
        } else {
            Text("Streaming")
                .font(metaFont)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Provider not listed")
        }
    }
}
