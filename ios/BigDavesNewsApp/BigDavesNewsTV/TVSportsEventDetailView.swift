import SwiftUI

struct TVSportsEventDetailView: View {
    let event: TVSportsEventItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionGap) {
                VStack(alignment: .leading, spacing: TVLayout.Spacing.s16) {
                    Text(event.displayStatus.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(statusColor)
                        .textCase(.uppercase)
                    Text(event.matchupLine)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.league)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(event.scoreOrTimeLine)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                    TVSectionHeader(title: "Game info", subtitle: nil)
                    VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                        if !event.statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(event.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let prov = event.footnoteProvider {
                            Text(prov)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                    TVSectionHeader(title: "Actions", subtitle: nil)
                    TVToolbarButton(title: "Back", accessibilityLabel: "Go back") {
                        dismiss()
                    }
                }
                .focusSection()
            }
            .padding(.horizontal, TVLayout.contentGutter)
            .padding(.vertical, TVLayout.sectionGap)
        }
        .background(TVLayout.appBackground)
    }

    private var statusColor: Color {
        switch event.displayStatus {
        case .live: return .red
        case .startingSoon: return .yellow
        case .scheduled: return .secondary
        }
    }
}
