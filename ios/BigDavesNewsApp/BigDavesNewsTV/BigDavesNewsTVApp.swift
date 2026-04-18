import SwiftUI

@main
struct BigDavesNewsTVApp: App {
    @StateObject private var homeModel = TVWatchHomeViewModel()

    var body: some Scene {
        WindowGroup {
            TVAppShell()
                .environmentObject(homeModel)
        }
    }
}
