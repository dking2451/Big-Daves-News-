import SwiftUI

struct RootTabView: View {
    @ObservedObject private var navigation = AppNavigationState.shared
    @ObservedObject private var sportsLiveStatus = SportsLiveStatus.shared
    @ObservedObject private var tonightMode = TonightModeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("bdn-personalization-onboarding-completed-v1") private var personalizationOnboardingDone = false
    @State private var showPersonalizationOnboarding = false
    @State private var showLaunchSplash = false

    var body: some View {
        ZStack {
            TabView(selection: $navigation.selectedTab) {
                HeadlinesView()
                    .tag(AppTab.headlines)
                    .tabItem {
                        Label("Headlines", systemImage: "newspaper")
                    }

                WatchView()
                    .tag(AppTab.watch)
                    .tabItem {
                        Label("Watch", systemImage: tonightMode.isActive ? "play.tv.fill" : "play.tv")
                    }

                BriefView()
                    .tag(AppTab.brief)
                    .tabItem {
                        Label("Brief", systemImage: "sunrise")
                    }

                SportsView()
                    .tag(AppTab.sports)
                    .tabItem {
                        Label("Sports", systemImage: tonightMode.isActive ? "sportscourt.fill" : "sportscourt")
                    }
                    .badge(sportsLiveStatus.hasLiveGames ? "LIVE" : nil)

                WeatherView()
                    .tag(AppTab.weather)
                    .tabItem {
                        Label("Weather", systemImage: "cloud.sun")
                    }
            }
            .tint(tonightMode.accentColor)

            if tonightMode.isActive {
                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.10 : 0.038),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.42)
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .environment(\.tonightModeActive, tonightMode.isActive)
        .dynamicTypeSize((DeviceLayout.isPad ? DynamicTypeSize.large : .xSmall) ... .accessibility3)
        .task {
            await SportsLiveStatus.shared.refreshIfNeeded(force: true)
            migrateLegacyOnboardingFlagIfNeeded()
            guard !personalizationOnboardingDone else { return }
            showLaunchSplash = true
            try? await Task.sleep(nanoseconds: 420_000_000)
            showLaunchSplash = false
            showPersonalizationOnboarding = true
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                tonightMode.refresh()
            }
        }
        .onChange(of: navigation.selectedTab) { tab in
            guard tab == .sports else { return }
            Task {
                await SportsLiveStatus.shared.refresh(force: true)
            }
        }
        .fullScreenCover(isPresented: $showPersonalizationOnboarding) {
            PersonalizationOnboardingContainer(isPresented: $showPersonalizationOnboarding)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bdnReplayPersonalizationOnboarding)) { _ in
            showPersonalizationOnboarding = true
        }
    }

    /// One-time: users who finished the older single-screen prefs flow shouldn’t see this again.
    private func migrateLegacyOnboardingFlagIfNeeded() {
        let legacy = "bdn-user-prefs-onboarding-completed"
        let newKey = "bdn-personalization-onboarding-completed-v1"
        if UserDefaults.standard.bool(forKey: legacy), !UserDefaults.standard.bool(forKey: newKey) {
            UserDefaults.standard.set(true, forKey: newKey)
            personalizationOnboardingDone = true
        }
    }
}
