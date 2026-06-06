import SwiftUI

// MARK: - Show Detail Sheet (phone)

struct WatchShowDetailSheet: View {
    let show: WatchShowItem
    let recommendationReason: String
    let onCycleWatchProgress: () -> Void
    let onReaction: (String) -> Void
    let onToggleSaved: (Bool) -> Void
    let onCaughtUp: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isPad: Bool { DeviceLayout.isPad }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    posterHero
                    contentBody
                        .padding(.horizontal, WatchDesign.spaceMD)
                        .padding(.top, WatchDesign.spaceMD)
                        .padding(.bottom, 40)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(show.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Poster hero

    private var posterHero: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Blurred background fill
                WatchShowPosterImage(
                    show: show,
                    width: geo.size.width,
                    height: geo.size.height,
                    cornerRadius: 0,
                    continuousCornerStyle: false,
                    showProgressWhenLoading: false,
                    placeholderSymbolFont: .largeTitle
                )
                .blur(radius: 32)
                .scaleEffect(1.15)
                .clipped()
                .overlay(Color.black.opacity(0.45))

                // Centered poster card
                WatchShowPosterImage(
                    show: show,
                    width: posterWidth,
                    height: posterHeight,
                    cornerRadius: WatchDesign.radiusCardLarge,
                    continuousCornerStyle: true,
                    showProgressWhenLoading: true,
                    placeholderSymbolFont: .largeTitle
                )
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                .padding(.bottom, WatchDesign.spaceMD)
            }
        }
        .frame(height: heroHeight)
    }

    private var posterWidth: CGFloat {
        DeviceLayout.isLargePad ? 200 : (isPad ? 170 : 130)
    }
    private var posterHeight: CGFloat { posterWidth * 1.5 }
    private var heroHeight: CGFloat { posterHeight + 56 }

    // MARK: Content body

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: WatchDesign.spaceMD) {
            // Title + badges
            titleRow

            // Provider + season meta
            metaRow

            // Streaming CTA
            StreamingProviderLaunchControl(show: show, style: .cardCompact)
                .frame(maxWidth: .infinity)

            // Action buttons
            WatchCardActionRow(
                show: show,
                onCycleWatchProgress: onCycleWatchProgress,
                onReaction: onReaction,
                onToggleSaved: onToggleSaved,
                onCaughtUp: onCaughtUp
            )

            Divider()

            // Synopsis
            detailSection(title: "About") {
                Text(show.synopsis)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Show details
            detailSection(title: "Details") {
                detailGrid
            }

            // Recommendation reason
            if !recommendationReason.isEmpty {
                Divider()
                detailSection(title: "Why this pick") {
                    HStack(alignment: .top, spacing: WatchDesign.spaceXS) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.primary)
                        Text(recommendationReason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .top, spacing: WatchDesign.spaceXS) {
            Text(show.title)
                .font(isPad ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                WatchListProgressBadge(state: show.watchProgressState)
                if let kind = WatchBadgeFormatting.primaryBadge(for: show, listIndex: nil, in: []) {
                    WatchBadge(kind: kind, compact: false, useSolidFill: true)
                }
            }
        }
    }

    // MARK: Meta row

    @ViewBuilder
    private var metaRow: some View {
        let parts: [String] = [
            show.primaryProvider ?? show.providers.first,
            show.seasonEpisodeStatus.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            runtimeLabel,
        ].compactMap { $0 }.filter { !$0.isEmpty }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        // Genre chips
        if !show.genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(show.genres.prefix(5), id: \.self) { genre in
                        Text(genre)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.primary.opacity(0.1))
                            .foregroundStyle(AppTheme.primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: Details grid

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let genre = show.primaryGenre {
                detailRow(label: "Genre", value: genre)
            }
            if let year = releaseYear {
                detailRow(label: "First aired", value: year)
            }
            if let last = show.lastEpisodeAirDate, !last.isEmpty {
                detailRow(label: "Last episode", value: formattedDate(last))
            }
            if let next = show.nextEpisodeAirDate, !next.isEmpty {
                detailRow(label: "Next episode", value: formattedDate(next))
            }
            if let runtime = show.episodeRuntime {
                detailRow(label: "Runtime", value: "~\(runtime) min per episode")
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Section wrapper

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WatchDesign.spaceXS) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
    }

    // MARK: Helpers

    private var runtimeLabel: String? {
        guard let r = show.episodeRuntime else { return nil }
        return "~\(r) min"
    }

    private var releaseYear: String? {
        let raw = show.releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "Unknown" else { return nil }
        return String(raw.prefix(4))
    }

    private func formattedDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmts = ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy"]
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        for fmt in fmts {
            let df = DateFormatter()
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) { return out.string(from: d) }
        }
        return trimmed
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
