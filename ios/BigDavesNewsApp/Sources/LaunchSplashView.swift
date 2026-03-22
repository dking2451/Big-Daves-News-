import SwiftUI

/// Brief branded splash for first launch (before personalization). Non-blocking; no artificial network waits.
struct LaunchSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("BDN")
                    .font(.title.weight(.black))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.2))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                Text("Big Daves News")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Big Daves News")
    }
}
