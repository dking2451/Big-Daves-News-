import SwiftUI

struct RootTabView: View {
    var body: some View {
        GeometryReader { geo in
            let isPadLandscape = DeviceLayout.isPad && geo.size.width > geo.size.height
            let minType: DynamicTypeSize = isPadLandscape ? .xLarge : (DeviceLayout.isPad ? .large : .xSmall)

            TabView {
                HeadlinesView()
                    .tabItem {
                        Label("Headlines", systemImage: "newspaper")
                    }

                WeatherView()
                    .tabItem {
                        Label("Weather", systemImage: "cloud.sun")
                    }

                BusinessView()
                    .tabItem {
                        Label("Business", systemImage: "chart.line.uptrend.xyaxis")
                    }

                WatchView()
                    .tabItem {
                        Label("Watch", systemImage: "play.tv")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .dynamicTypeSize(minType ... .accessibility3)
        }
    }
}
