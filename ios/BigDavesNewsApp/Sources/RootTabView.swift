import SwiftUI

struct RootTabView: View {
    @ObservedObject private var navigation = AppNavigationState.shared

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

            WeatherView()
                .tag(AppTab.weather)
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun")
                }

            BusinessView()
                .tag(AppTab.business)
                .tabItem {
                    Label("Business", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
        .dynamicTypeSize((DeviceLayout.isPad ? DynamicTypeSize.large : .xSmall) ... .accessibility3)
    }
}
