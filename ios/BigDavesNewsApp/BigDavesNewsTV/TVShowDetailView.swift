import SwiftUI

struct TVShowDetailView: View {
    let show: TVWatchShowItem
    @EnvironmentObject private var homeModel: TVWatchHomeViewModel
    @Environment(\.dismiss) private var dismiss

    private var profile: ComposedUserProfile? { homeModel.composedProfile }

    private var savedIds: Set<String> {
        let p = Set(profile?.watchBlock.savedShowIds ?? [])
        let h = Set(homeModel.allItems.filter { $0.saved == true }.map(\.id))
        let m = Set(homeModel.myListItems.map(\.id))
        return p.union(h).union(m)
    }

    private var isSaved: Bool { savedIds.contains(show.id) }

    private var effectiveProgress: WatchProgressTV {
        if let m = profile?.watchBlock.watchStateByShow,
           let raw = m[show.id]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        {
            if raw == "watching" { return .watching }
            if raw == "finished" { return .finished }
            if raw == "not_started" { return .notStarted }
        }
        return show.watchProgressState
    }

    private var openTitle: String {
        TVProviderCatalog.definition(primary: show.primaryProvider, providers: show.providers)?
            .primaryActionTitle ?? "Open to watch"
    }

    private var watchStatusLabel: String {
        switch effectiveProgress {
        case .notStarted: return "Not started"
        case .watching: return "Watching"
        case .finished: return "Finished"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionGap) {
                topBackdrop
                actionsStack
                metadataStack
            }
            .padding(.horizontal, TVLayout.contentGutter)
            .padding(.vertical, TVLayout.sectionGap)
        }
        .background(TVLayout.appBackground)
    }

    // MARK: - Top (backdrop + context; matches Home hero rhythm)

    private var topBackdrop: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = show.posterRemoteURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            backdropFallback
                        }
                    }
                } else {
                    backdropFallback
                }
            }
            .frame(height: TVLayout.detailBackdropHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            LinearGradient(
                colors: [TVTheme.heroGradientTop, TVTheme.heroGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                Text(show.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                    Text(p)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                if let r = show.recommendationReason, !r.isEmpty {
                    Text(r)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, TVLayout.Spacing.s24)
            .padding(.bottom, TVLayout.Spacing.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: TVLayout.radiusCard, style: .continuous))
    }

    private var backdropFallback: some View {
        ZStack {
            TVLayout.heroPlaceholderFill
            Image(systemName: "tv.inset.filled")
                .font(.system(size: TVLayout.placeholderIconSize))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions (only place for watch mutations)

    private var actionsStack: some View {
        VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
            TVSectionHeader(title: "Actions", subtitle: nil)
            VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                TVPrimaryButton(title: openTitle) {
                    Task { await TVProviderCatalog.open(show) }
                }
                TVSecondaryButton(
                    title: isSaved ? "Remove from My List" : "Add to My List",
                    accessibilityLabel: isSaved ? "Remove from My List" : "Add to My List"
                ) {
                    toggleSaved()
                }
                TVSecondaryButton(title: "Mark Watching", accessibilityLabel: "Mark Watching") {
                    setWatchProgress(.watching)
                }
                TVSecondaryButton(title: "Mark Finished", accessibilityLabel: "Mark Finished") {
                    setWatchProgress(.finished)
                }
                TVToolbarButton(title: "Back", accessibilityLabel: "Go back") {
                    dismiss()
                }
            }
        }
        .focusSection()
    }

    // MARK: - Metadata

    private var metadataStack: some View {
        VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
            TVSectionHeader(title: "Details", subtitle: nil)
            VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                labeledRow(label: "Watch status", value: watchStatusLabel)
                if !show.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(show.synopsis)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !show.genres.isEmpty {
                    Text(show.genres.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let pg = show.primaryGenre?.trimmingCharacters(in: .whitespacesAndNewlines), !pg.isEmpty, show.genres.isEmpty {
                    Text(pg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !show.seasonEpisodeStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labeledRow(label: "Status", value: show.seasonEpisodeStatus)
                }
                let rd = show.releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rd.isEmpty {
                    labeledRow(label: "Release", value: rd)
                }
            }
        }
    }

    private func labeledRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: TVLayout.Spacing.s8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func toggleSaved() {
        var ids = savedIds
        if isSaved {
            ids.remove(show.id)
        } else {
            ids.insert(show.id)
        }
        let patch: [String: Any] = ["saved_show_ids": Array(ids).sorted()]
        ProfileSyncCoordinator.shared.applyWatchPatchLocally(watchPatch: patch)
        homeModel.syncComposedProfileWithCoordinator()
        Task {
            await ProfileSyncCoordinator.shared.applyWatchPatchSyncNetworkOnly(watchPatch: patch)
            await MainActor.run { homeModel.syncComposedProfileWithCoordinator() }
            await homeModel.refreshAfterProfileMutation()
        }
    }

    private func setWatchProgress(_ next: WatchProgressTV) {
        let patch: [String: Any] = ["watch_state_by_show": [show.id: next.rawValue]]
        ProfileSyncCoordinator.shared.applyWatchPatchLocally(watchPatch: patch)
        homeModel.syncComposedProfileWithCoordinator()
        Task {
            await ProfileSyncCoordinator.shared.applyWatchPatchSyncNetworkOnly(watchPatch: patch)
            await MainActor.run { homeModel.syncComposedProfileWithCoordinator() }
            await homeModel.refreshAfterProfileMutation()
        }
    }
}
