import SwiftUI
import UserNotifications

extension Notification.Name {
    /// Posted from `UIApplicationDelegate` when the system opens a URL (backup for SwiftUI `onOpenURL`).
    static let familyOSOpenImportURL = Notification.Name("familyOSOpenImportURL")
}

private struct ImportSheetItem: Identifiable {
    let id = UUID()
    let payload: ShareHandoff.Payload
}

/// Onboarding vs tabs; presents Share Extension import with minimal state (no separate router type).
struct RootContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("didRequestShareImportNotifyPermission") private var didRequestShareImportNotifyPermission = false

    @EnvironmentObject private var store: EventStore
    @Environment(\.scenePhase) private var scenePhase

    /// Active handoff from the App Group (`consume()`), URL fallback, or nil.
    @State private var importSheetItem: ImportSheetItem?

    var body: some View {
        Group {
            if hasSeenOnboarding {
                MainTabView()
            } else {
                WelcomeView(onContinue: { hasSeenOnboarding = true })
            }
        }
        .onOpenURL(perform: handleImportURL)
        .onReceive(NotificationCenter.default.publisher(for: .familyOSOpenImportURL)) { notification in
            if let url = notification.object as? URL {
                handleImportURL(url)
            }
        }
        .onAppear {
            Task { @MainActor in
                if hasSeenOnboarding {
                    await requestShareImportNotifyPermissionIfNeeded()
                }
                consumeHandoffIntoSheet()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { @MainActor in
                    consumeHandoffIntoSheet()
                }
            }
        }
        .onChange(of: hasSeenOnboarding) { _, isOnboarded in
            if isOnboarded {
                Task { @MainActor in
                    await requestShareImportNotifyPermissionIfNeeded()
                    consumeHandoffIntoSheet()
                }
            }
        }
        .sheet(item: $importSheetItem, onDismiss: {
            Task { @MainActor in
                consumeHandoffIntoSheet()
            }
        }) { item in
            NavigationStack {
                ShareImportView(payload: item.payload)
                    .environmentObject(store)
            }
            .familyBrandToolbarIcon()
            .onDisappear {
                ShareHandoff.discardImageIfNeeded(for: item.payload)
            }
        }
    }

    /// Handles `familyosmvp://import` from SwiftUI and from `UIApplicationDelegate`.
    private func handleImportURL(_ url: URL) {
        guard isFamilyOSImportDeepLink(url) else { return }
        Task { @MainActor in
            processImportURL(url)
        }
    }

    @MainActor
    private func processImportURL(_ url: URL) {
        guard importSheetItem == nil else { return }
        if let payload = importPayloadFromURLQuery(url) {
            importSheetItem = ImportSheetItem(payload: payload)
            ShareImportNotifier.clearImportReadyNotificationForHandledShare()
            return
        }
        consumeHandoffIntoSheet()
    }

    /// Accepts `familyosmvp://import` and `familyosmvp:///import` (host vs path variants).
    private func isFamilyOSImportDeepLink(_ url: URL) -> Bool {
        guard url.scheme == "familyosmvp" else { return false }
        if url.host == "import" { return true }
        if url.host == nil || url.host?.isEmpty == true {
            let p = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return p == "import"
        }
        return false
    }

    @MainActor
    private func consumeHandoffIntoSheet() {
        guard importSheetItem == nil else { return }
        guard let payload = ShareHandoff.consume() else { return }
        importSheetItem = ImportSheetItem(payload: payload)
        ShareImportNotifier.clearImportReadyNotificationForHandledShare()
    }

    /// Encourages permission early so the Share Extension can schedule the “Import ready” nudge; extension also requests if still undetermined.
    private func requestShareImportNotifyPermissionIfNeeded() async {
        guard !didRequestShareImportNotifyPermission else { return }
        didRequestShareImportNotifyPermission = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func importPayloadFromURLQuery(_ url: URL) -> ShareHandoff.Payload? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let value = components.queryItems?.first(where: { $0.name == "text" })?.value, !value.isEmpty else {
            return nil
        }

        guard let decoded = decodeBase64URLSafe(value) else { return nil }
        return .text(decoded)
    }

    private func decodeBase64URLSafe(_ input: String) -> String? {
        var b64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Restore padding.
        let remainder = b64.count % 4
        if remainder != 0 {
            b64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
