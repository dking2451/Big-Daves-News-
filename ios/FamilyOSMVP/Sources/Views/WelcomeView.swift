import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.blue)

            Text("Family OS MVP")
                .font(.largeTitle.weight(.bold))

            Text("A calm way to manage kid schedules, review AI suggestions, and stay on top of this week.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(Color(.systemBackground))
    }
}
