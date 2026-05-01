import SwiftUI

/// A slim banner shown when a tab is displaying cached data due to a network failure.
/// Disappears automatically once fresh data loads.
struct BDNStaleBanner: View {
    let age: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
            Text("Showing saved data from \(age). Pull to refresh.")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .fill(Color.orange.opacity(0.85))
        )
        .accessibilityLabel("Showing cached data from \(age). Pull down to refresh.")
    }
}
