import SwiftUI

/// Lightweight inspector for server `rank_debug` + optional Tonight runner-ups (long-press on a Watch card).
struct WatchRankDebugSheet: View {
    let show: WatchShowItem
    /// Full response section: closest Tonight also-rans + excluded sample (hero long-press only).
    var tonightSection: WatchRankTonightSection?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(show.title)
                        .font(.headline)
                    if let d = show.rankDebug {
                        rankBlock(d)
                        if show.rankDebug?.surface == "tonight_pick", let t = tonightSection {
                            tonightExtras(t)
                        }
                    } else {
                        Text(
                            "No rank_debug on this item. Set ALLOW_WATCH_RANK_DEBUG=1 on the API and request with debug_rank=1 (see Debug toggle in Watch refresh path)."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Rank debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func rankBlock(_ d: WatchRankItemDebugPayload) -> some View {
        Group {
            keyValue("Surface", d.surface ?? "—")
            keyValue("Reason key", d.recommendationReasonKey ?? "—")
            keyValue("Rank reason (UX)", show.recommendationReason ?? "—")
            keyValue("rank_score", d.rankScore.map { String(format: "%.2f", $0) } ?? "—")
            keyValue("trend_score", d.trendScore.map { String(format: "%.2f", $0) } ?? "—")
            keyValue("final_computed", d.finalComputedScore.map { String(format: "%.2f", $0) } ?? "—")
            keyValue("watch_state", d.watchState ?? "—")
            keyValue("saved / liked / passed", savedLine(d))
            if let div = d.diversityRankDelta, div != 0 {
                keyValue("diversity Δ slots", String(div))
                keyValue("diversity note", d.diversityNote ?? "")
            }
            if let roll = d.rollupScores, !roll.isEmpty {
                Text("Rollups (tuning lens)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                ForEach(roll.keys.sorted(), id: \.self) { k in
                    keyValue(k, String(format: "%.2f", roll[k] ?? 0))
                }
            }
            if let pos = d.topPositiveFactors, !pos.isEmpty {
                Text("Top positive factors")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                ForEach(pos, id: \.key) { row in
                    keyValue(row.key, String(format: "%.3f", row.value))
                }
            }
            if let neg = d.topPenalties, !neg.isEmpty {
                Text("Top penalties")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                ForEach(neg, id: \.key) { row in
                    keyValue(row.key, String(format: "%.3f", row.value))
                }
            }
            if let flat = d.componentsFlat, !flat.isEmpty {
                Text("components_flat (full)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                ForEach(flat.keys.sorted(), id: \.self) { k in
                    keyValue(k, String(format: "%.4f", flat[k] ?? 0))
                }
            }
        }
    }

    private func savedLine(_ d: WatchRankItemDebugPayload) -> String {
        "\(d.isSaved == true ? "Y" : "n") / \(d.isLiked == true ? "Y" : "n") / \(d.isPassed == true ? "Y" : "n")"
    }

    @ViewBuilder
    private func tonightExtras(_ t: WatchRankTonightSection) -> some View {
        if let note = t.note, !note.isEmpty {
            Text("Tonight note: \(note)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        if let ru = t.runnerUps, !ru.isEmpty {
            Text("Tonight also-rans")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)
            ForEach(Array(ru.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.title ?? r.showId ?? "—")
                        .font(.caption.weight(.semibold))
                    if let g = r.gapVsWinner {
                        Text(String(format: "Δ vs winner: %.2f", g))
                            .font(.caption2.monospaced())
                    }
                    if let why = r.whyBelowWinner {
                        Text(why)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        if let ex = t.excludedSample, !ex.isEmpty {
            Text("Tonight excluded sample (\(t.excludedCount ?? ex.count))")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)
            ForEach(Array(ex.enumerated()), id: \.offset) { _, row in
                Text("\(row.title ?? row.showId ?? "") — \(row.excludedReason ?? "")")
                    .font(.caption2)
            }
        }
    }

    private func keyValue(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(v)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
