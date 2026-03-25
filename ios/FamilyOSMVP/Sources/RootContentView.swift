import SwiftUI

/// Onboarding vs tabs; presents Share Extension import with minimal state (no separate router type).
struct RootContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @EnvironmentObject private var store: EventStore

    /// Active handoff from the App Group (set by `consume()` or nil).
    @State private var importPayload: ShareHandoff.Payload?

    var body: some View {
        Group {
            if hasSeenOnboarding {
                MainTabView()
            } else {
                WelcomeView(onContinue: { hasSeenOnboarding = true })
            }
        }
        .onOpenURL { url in
            guard url.scheme == "familyosmvp", url.host == "import" else { return }
            consumeHandoffIntoSheet()
        }
        .onAppear(perform: consumeHandoffIntoSheet)
        .onChange(of: hasSeenOnboarding) { _, isOnboarded in
            if isOnboarded { consumeHandoffIntoSheet() }
        }
        .sheet(isPresented: importSheetBinding) {
            if let payload = importPayload {
                NavigationStack {
                    ShareImportView(payload: payload)
                        .environmentObject(store)
                }
                .familyBrandToolbarIcon()
            }
        }
    }

    private var importSheetBinding: Binding<Bool> {
        Binding(
            get: { importPayload != nil },
            set: { newValue in
                if !newValue {
                    if let payload = importPayload {
                        ShareHandoff.discardImageIfNeeded(for: payload)
                    }
                    importPayload = nil
                    DispatchQueue.main.async { consumeHandoffIntoSheet() }
                }
            }
        )
    }

    private func consumeHandoffIntoSheet() {
        guard importPayload == nil else { return }
        guard let payload = ShareHandoff.consume() else { return }
        importPayload = payload
    }
}
