import SwiftUI

struct RootTabView: View {
    @ObservedObject private var navigation = AppNavigationState.shared
    @ObservedObject private var sportsLiveStatus = SportsLiveStatus.shared

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            HeadlinesView()
                .tag(AppTab.headlines)
                .tabItem {
                    Label("Headlines", systemImage: "newspaper")
                }

            WatchView()
                .tag(AppTab.watch)
                .tabItem {
                    Label("Watch", systemImage: "play.tv")
                }

            BriefView()
                .tag(AppTab.brief)
                .tabItem {
                    Label("Brief", systemImage: "sunrise")
                }

            SportsView()
                .tag(AppTab.sports)
                .tabItem {
                    Label("Sports", systemImage: "sportscourt")
                }
                .badge(sportsLiveStatus.hasLiveGames ? "LIVE" : nil)

            WeatherView()
                .tag(AppTab.weather)
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun")
                }
        }
        .dynamicTypeSize((DeviceLayout.isPad ? DynamicTypeSize.large : .xSmall) ... .accessibility3)
        .task {
            await SportsLiveStatus.shared.refreshIfNeeded(force: true)
        }
        .onChange(of: navigation.selectedTab) { tab in
            guard tab == .sports else { return }
            Task {
                await SportsLiveStatus.shared.refresh(force: true)
            }
        }
    }
}
