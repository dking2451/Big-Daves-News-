import SwiftUI

@main
struct FamilyOSMVPApp: App {
    @StateObject private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(store)
        }
    }
}
