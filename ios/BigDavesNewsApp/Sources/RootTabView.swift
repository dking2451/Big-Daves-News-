import SwiftUI
import UIKit
import Foundation

struct RootTabView: View {
    @ObservedObject private var navigation = AppNavigationState.shared
    @ObservedObject private var sportsLiveStatus = SportsLiveStatus.shared
    @ObservedObject private var headlinesBadge = HeadlinesBadgeState.shared
    @AppStorage("bdn-personalization-onboarding-completed-v1") private var personalizationOnboardingDone = false
    @State private var showPersonalizationOnboarding = false
    @State private var showLaunchSplash = false

    private var tabItems: [BDNTabBar.Item] {
        [
            .init(tab: .headlines, systemName: "newspaper", label: "Headlines", showsLiveDot: headlinesBadge.unreadCount > 0),
            .init(tab: .watch, systemName: "play.tv", label: "Watch"),
            .init(tab: .brief, systemName: "sunrise", label: "Brief"),
            .init(tab: .sports, systemName: "sportscourt", label: "Sports", showsLiveDot: sportsLiveStatus.hasLiveGames),
            .init(tab: .weather, systemName: "cloud.sun", label: "Weather"),
        ]
    }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            HeadlinesView().tag(AppTab.headlines)
            WatchView().tag(AppTab.watch)
            BriefView().tag(AppTab.brief)
            SportsView().tag(AppTab.sports)
            WeatherView().tag(AppTab.weather)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BDNTabBar(items: tabItems, selection: $navigation.selectedTab)
                .padding(.top, 14)
                .background {
                    // Short fade at the very top so content dissolves as it reaches the
                    // bar, then solid page background behind and below the floating pill
                    // so nothing ghosts through the glass or under its shadow.
                    LinearGradient(
                        stops: [
                            .init(color: AppTheme.pageBackground.opacity(0), location: 0.0),
                            .init(color: AppTheme.pageBackground, location: 0.22),
                            .init(color: AppTheme.pageBackground, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
        }
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
        .onChange(of: navigation.selectedTab) { _, tab in
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

    private func migrateLegacyOnboardingFlagIfNeeded() {
        let legacy = "bdn-user-prefs-onboarding-completed"
        let newKey = "bdn-personalization-onboarding-completed-v1"
        if UserDefaults.standard.bool(forKey: legacy), !UserDefaults.standard.bool(forKey: newKey) {
            UserDefaults.standard.set(true, forKey: newKey)
            personalizationOnboardingDone = true
        }
    }
}
