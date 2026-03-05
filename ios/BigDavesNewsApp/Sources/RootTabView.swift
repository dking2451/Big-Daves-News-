import SwiftUI

struct RootTabView: View {
    var body: some View {
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

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
