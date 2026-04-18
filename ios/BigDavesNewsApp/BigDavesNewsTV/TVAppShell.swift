import SwiftUI

/// Primary tab identifiers for the tvOS shell (Apple TV–style top tab bar).
enum TVAppTab: Hashable {
    case home
    case myList
    case sports
    case ocho
}

/// Single navigation + tab container: shared `TVWatchHomeViewModel` and per-tab `NavigationStack`s.
struct TVAppShell: View {
    @EnvironmentObject private var homeModel: TVWatchHomeViewModel
    @State private var selectedTab: TVAppTab = .home
    @State private var homePath = NavigationPath()
    @State private var myListPath = NavigationPath()
    @State private var sportsPath = NavigationPath()
    @State private var ochoPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                TVWatchHomeView { show in
                    homePath.append(show)
                }
                .navigationTitle("Home")
                .navigationDestination(for: TVWatchShowItem.self) { show in
                    TVShowDetailView(show: show)
                }
            }
            .animation(TVFocusMotion.animation, value: homePath.count)
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(TVAppTab.home)

            NavigationStack(path: $myListPath) {
                TVMyListView { show in
                    myListPath.append(show)
                }
                .navigationTitle("My List")
                .navigationDestination(for: TVWatchShowItem.self) { show in
                    TVShowDetailView(show: show)
                }
            }
            .animation(TVFocusMotion.animation, value: myListPath.count)
            .tabItem { Label("My List", systemImage: "list.bullet") }
            .tag(TVAppTab.myList)

            NavigationStack(path: $sportsPath) {
                TVSportsView { event in
                    sportsPath.append(event)
                }
                .navigationTitle("Sports")
                .navigationDestination(for: TVSportsEventItem.self) { event in
                    TVSportsEventDetailView(event: event)
                }
            }
            .animation(TVFocusMotion.animation, value: sportsPath.count)
            .tabItem { Label("Sports", systemImage: "sportscourt") }
            .tag(TVAppTab.sports)

            NavigationStack(path: $ochoPath) {
                TVOchoView { event in
                    ochoPath.append(event)
                }
                .navigationTitle("Ocho")
                .navigationDestination(for: TVSportsEventItem.self) { event in
                    TVSportsEventDetailView(event: event)
                }
            }
            .animation(TVFocusMotion.animation, value: ochoPath.count)
            .tabItem { Label("Ocho", systemImage: "sparkles") }
            .tag(TVAppTab.ocho)
        }
        .tint(TVTheme.accent)
        .animation(TVFocusMotion.animation, value: selectedTab)
    }
}
