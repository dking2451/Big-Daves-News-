import SwiftUI

/// First-run onboarding: short pages so TestFlight testers know what to try first.
struct WelcomeView: View {
    let onContinue: () -> Void

    @State private var page = 0
    private let lastPageIndex = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomeIntroPage
                    .tag(0)
                addEventsPage
                    .tag(1)
                importAndSettingsPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: 12) {
                Button {
                    if page < lastPageIndex {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            page += 1
                        }
                    } else {
                        onContinue()
                    }
                } label: {
                    Text(page < lastPageIndex ? "Next" : "Get started")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(page < lastPageIndex ? "Shows the next tip" : "Opens the app")

                if page > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            page -= 1
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .padding(.top, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Pages

    private var welcomeIntroPage: some View {
        onboardingPage(
            icon: "calendar.badge.clock",
            iconTint: .blue,
            title: "Family OS MVP",
            paragraphs: [
                "See your kids’ upcoming plans in one calm place.",
                "Your schedule stays on this device—no accounts required for this MVP.",
            ]
        )
    }

    private var addEventsPage: some View {
        onboardingPage(
            icon: "plus.circle.fill",
            iconTint: .accentColor,
            title: "Add events",
            paragraphs: [
                "On Home, use Quick Add for a fast entry, or the pencil button for the full form—category, repeats, and who’s driving (Mom, Dad, Either, or leave unassigned).",
                "Browse and filter everything under the Upcoming tab.",
            ]
        )
    }

    private var importAndSettingsPage: some View {
        onboardingPage(
            icon: "square.and.arrow.down.on.square",
            iconTint: .indigo,
            title: "Import & family",
            paragraphs: [
                "Paste text from the Home toolbar, or share from another app into Family OS when you’ve set up the Share extension.",
                "Add children in Settings to tune colors and defaults. You can clear local data anytime under Data.",
            ]
        )
    }

    private func onboardingPage(
        icon: String,
        iconTint: Color,
        title: String,
        paragraphs: [String]
    ) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 24)
        }
    }
}
