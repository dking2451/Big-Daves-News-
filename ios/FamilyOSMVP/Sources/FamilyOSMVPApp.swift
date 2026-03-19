import SwiftUI

@main
struct FamilyOSMVPApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @StateObject private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                MainTabView()
                    .environmentObject(store)
            } else {
                WelcomeView(onContinue: { hasSeenOnboarding = true })
            }
        }
    }
}
