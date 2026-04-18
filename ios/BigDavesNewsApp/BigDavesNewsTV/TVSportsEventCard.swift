import SwiftUI

/// Sports rail card: matches `TVPosterCard` frame and `TVLayout.radiusCard`; status uses `TVBadge`.
struct TVSportsEventCard: View {
    let event: TVSportsEventItem
    /// Slightly elevated surface + purple league tint (Ocho tab only).
    var ochoChrome: Bool = false
    /// Natural phrasing on status pill (Ocho tab only).
    var naturalMicrocopy: Bool = false
    /// Kept after optional chrome flags so call sites can use a trailing closure.
    let action: () -> Void

    private var cardFill: Color {
        ochoChrome ? Color.white.opacity(0.085) : TVTheme.cardBackground
    }

    private var badgeStyle: TVBadge.Style {
        switch event.displayStatus {
        case .live: return .live
        case .startingSoon: return .startingSoon
        case .scheduled: return .scheduled
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: TVLayout.radiusCard, style: .continuous)
                        .fill(cardFill)
                    VStack(alignment: .leading, spacing: TVLayout.Spacing.s12) {
                        TVBadge(
                            text: event.statusPillText(naturalMicrocopy: naturalMicrocopy),
                            style: badgeStyle,
                            usesUppercase: !naturalMicrocopy
                        )
                        Spacer(minLength: 0)
                        Text(event.matchupLine)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                        Text(event.scoreOrTimeLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(TVLayout.Spacing.s16)
                    .frame(
                        width: TVLayout.cardPosterWidth,
                        height: TVLayout.cardPosterHeight,
                        alignment: .topLeading
                    )
                }
                .frame(
                    width: TVLayout.cardPosterWidth,
                    height: TVLayout.cardPosterHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: TVLayout.radiusCard, style: .continuous))
                Text(event.league)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ochoChrome ? TVOchoTheme.accent : Color.primary)
                    .lineLimit(2)
                    .frame(width: TVLayout.cardPosterWidth, alignment: .leading)
                if let foot = event.footnoteProvider, !foot.isEmpty {
                    Text(foot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .tvFocusInteractive(.card)
        .accessibilityLabel("\(event.matchupLine), \(event.statusPillText(naturalMicrocopy: naturalMicrocopy))")
    }
}
