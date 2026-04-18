import SwiftUI

@MainActor
final class TVOchoViewModel: ObservableObject {
    @Published private(set) var events: [TVSportsEventItem] = []
    @Published var isLoading = true
    @Published var loadError: String?

    func load() async {
        isLoading = true
        loadError = nil
        do {
            var fetched = try await TVAPIClient.shared.fetchSportsNow(
                deviceId: SyncedUserIdentity.apiUserKey,
                windowHours: 12,
                timezoneName: TimeZone.current.identifier,
                includeOcho: true
            )
            if fetched.isEmpty {
                fetched = try await TVAPIClient.shared.fetchSportsNow(
                    deviceId: SyncedUserIdentity.apiUserKey,
                    windowHours: 12,
                    timezoneName: TimeZone.current.identifier,
                    includeOcho: false
                )
            }
            events = fetched
        } catch {
            loadError = TVShellErrorCopy.title
            events = []
        }
        if events
            .filter({ !$0.isOchoFallbackStub })
            .isEmpty
        {
            events = [TVSportsEventItem.ochoFallbackTuneIn()]
        }
        isLoading = false
    }

    private func active(_ list: [TVSportsEventItem]) -> [TVSportsEventItem] {
        list.filter { !$0.isFinal }
    }

    private func ochoRank(_ e: TVSportsEventItem) -> Int {
        var s = 0
        if e.isLive, e.isOchoPipelineRow { s += 60 }
        if e.isAltSport == true { s += 24 }
        if e.isEspnExtendedSource { s += 18 }
        if e.isCuratedSource { s += 12 }
        if e.ochoPromotedFromCore == true { s += 8 }
        if e.isLive { s += 10 }
        if let r = e.rankingScore { s += Int(min(12, max(0, r))) }
        return s
    }

    private func sortOcho(_ rows: [TVSportsEventItem]) -> [TVSportsEventItem] {
        rows.sorted { lhs, rhs in
            let lw = ochoRank(lhs)
            let rw = ochoRank(rhs)
            if lw != rw { return lw > rw }
            if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
            return lhs.startsInMinutes < rhs.startsInMinutes
        }
    }

    var liveNowRail: [TVSportsEventItem] {
        let rows = active(events).filter { $0.isLive || $0.resolvedTimingLabel() == "live_now" }
        return sortOcho(rows)
    }

    var startingSoonRail: [TVSportsEventItem] {
        let rows = active(events).filter {
            !$0.isLive && $0.resolvedTimingLabel() == "starting_soon"
        }
        return sortOcho(rows)
    }

    var tonightRail: [TVSportsEventItem] {
        let rows = active(events).filter {
            !$0.isLive && $0.resolvedTimingLabel() == "tonight"
        }
        return sortOcho(rows)
    }

    /// Curated / alt / extended feed rows not already placed in timed rails; otherwise any remaining; never empty when `events` non-empty.
    var worthALookRail: [TVSportsEventItem] {
        let pool = active(events)
        var used = Set<String>()
        liveNowRail.forEach { used.insert($0.id) }
        startingSoonRail.forEach { used.insert($0.id) }
        tonightRail.forEach { used.insert($0.id) }

        let pipelineRemaining = pool.filter {
            !used.contains($0.id) && ($0.isOchoPipelineRow || $0.ochoPromotedFromCore == true)
        }
        if !pipelineRemaining.isEmpty {
            return sortOcho(pipelineRemaining)
        }
        let anyRemaining = pool.filter { !used.contains($0.id) }
        if !anyRemaining.isEmpty {
            return sortOcho(anyRemaining)
        }

        if liveNowRail.isEmpty && startingSoonRail.isEmpty && tonightRail.isEmpty && !pool.isEmpty {
            return sortOcho(pool)
        }

        return []
    }

    /// True when any rail below the Live row can carry content (stub “tonight” row counts).
    var hasNonLiveOchoRails: Bool {
        !startingSoonRail.isEmpty || !tonightRail.isEmpty || !worthALookRail.isEmpty
    }

    var showNoLiveMessaging: Bool {
        !isLoading && liveNowRail.isEmpty && hasNonLiveOchoRails
    }

    var surpriseCandidates: [TVSportsEventItem] {
        let merged = liveNowRail + startingSoonRail + tonightRail + worthALookRail
        let unique = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) }).map(\.value)
        return unique.filter { !$0.isOchoFallbackStub }
    }

    var hasRealOchoData: Bool {
        events.contains { !$0.isOchoFallbackStub }
    }

    func pickSurprise() -> TVSportsEventItem? {
        surpriseCandidates.randomElement()
    }
}

// MARK: - Header (Sasquatch asset + Ocho copy; purple accent only here and primary actions)

struct TVOchoHeaderView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    TVOchoTheme.headerGlow.opacity(0.75),
                    TVOchoTheme.background,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.black.opacity(0.12), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(alignment: .bottom, spacing: TVLayout.Spacing.s24) {
                VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                    Text("THE OCHO")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                    Text("Alt Sports")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(TVOchoTheme.accent)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    Text("Live, weird, and worth watching")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("SasquatchOcho")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: TVLayout.radiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TVLayout.radiusSmall, style: .continuous)
                            .stroke(TVOchoTheme.accent.opacity(0.9), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    .accessibilityLabel("The Ocho: Sasquatch mascot")
            }
            .padding(.horizontal, TVLayout.contentGutter)
            .padding(.top, TVLayout.Spacing.s24)
            .padding(.bottom, TVLayout.Spacing.s24)
        }
        .frame(height: TVLayout.ochoHeaderHeight)
        .frame(maxWidth: .infinity)
        .overlay(
            Rectangle()
                .stroke(TVOchoTheme.accent.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Screen

struct TVOchoView: View {
    @EnvironmentObject private var homeModel: TVWatchHomeViewModel
    @StateObject private var ochoModel = TVOchoViewModel()
    var onSelectEvent: (TVSportsEventItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionGap) {
                TVOchoHeaderView()

                TVPrimaryButton(title: "Surprise Me", tint: TVOchoTheme.accent) {
                    if let ev = ochoModel.pickSurprise() {
                        onSelectEvent(ev)
                    }
                }
                .disabled(ochoModel.surpriseCandidates.isEmpty)
                .opacity(ochoModel.surpriseCandidates.isEmpty ? 0.45 : 1)
                .padding(.horizontal, TVLayout.contentGutter)

                if ochoModel.isLoading && ochoModel.events.isEmpty {
                    ProgressView("Loading THE OCHO…")
                        .padding(.top, TVLayout.Spacing.s24 * 5)
                        .frame(maxWidth: .infinity)
                } else {
                    if ochoModel.showNoLiveMessaging {
                        VStack(spacing: TVLayout.Spacing.s12) {
                            Text("Nothing live right now")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                            Text("But something’s always coming up")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, TVLayout.contentGutter)
                    }

                    if !ochoModel.liveNowRail.isEmpty {
                        TVContentRail(
                            title: "Live Now",
                            subtitle: TVSportsRailCopy.liveSubtitle,
                            subtitleTint: TVOchoTheme.accent.opacity(0.92)
                        ) {
                            ForEach(ochoModel.liveNowRail) { event in
                                TVSportsEventCard(event: event, ochoChrome: true, naturalMicrocopy: true) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                    if !ochoModel.startingSoonRail.isEmpty {
                        TVContentRail(
                            title: "Starting Soon",
                            subtitle: TVSportsRailCopy.startingSoonSubtitle,
                            subtitleTint: TVOchoTheme.accent.opacity(0.92)
                        ) {
                            ForEach(ochoModel.startingSoonRail) { event in
                                TVSportsEventCard(event: event, ochoChrome: true, naturalMicrocopy: true) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                    if !ochoModel.tonightRail.isEmpty {
                        TVContentRail(
                            title: "Tonight",
                            subtitle: TVSportsRailCopy.tonightSubtitle,
                            subtitleTint: TVOchoTheme.accent.opacity(0.85)
                        ) {
                            ForEach(ochoModel.tonightRail) { event in
                                TVSportsEventCard(event: event, ochoChrome: true, naturalMicrocopy: true) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                    if !ochoModel.worthALookRail.isEmpty {
                        TVContentRail(
                            title: "Worth a Look",
                            subtitle: "Hand-picked and alt feeds",
                            subtitleTint: TVOchoTheme.accent.opacity(0.92)
                        ) {
                            ForEach(ochoModel.worthALookRail) { event in
                                TVSportsEventCard(event: event, ochoChrome: true, naturalMicrocopy: true) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                }

                if ochoModel.loadError != nil, !ochoModel.hasNonLiveOchoRails, !ochoModel.isLoading {
                    TVEmptyStateMessage(
                        title: TVShellErrorCopy.title,
                        subtitle: TVShellErrorCopy.subtitle,
                        retryTitle: "Try again",
                        retryAction: {
                            Task {
                                await homeModel.ensureProfileLoaded()
                                await ochoModel.load()
                            }
                        }
                    )
                } else if let err = ochoModel.loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVLayout.contentGutter)
                }
            }
            .padding(.top, TVLayout.screenTopInset)
        }
        .background(TVOchoTheme.background)
        .task {
            await homeModel.ensureProfileLoaded()
            await ochoModel.load()
        }
        .onAppear {
            if ochoModel.events.isEmpty, !ochoModel.isLoading {
                Task {
                    await homeModel.ensureProfileLoaded()
                    await ochoModel.load()
                }
            }
        }
    }
}
