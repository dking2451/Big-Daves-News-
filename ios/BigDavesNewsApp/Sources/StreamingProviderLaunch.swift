import SwiftUI
import UIKit

// MARK: - Provider configuration (single source of truth)

/// Describes how to open a streaming app or fall back for a given service.
/// Tune URLs as provider APIs change; keep `querySchemes` in sync with `Info.plist` → `LSApplicationQueriesSchemes`.
struct StreamingProviderDefinition: Identifiable, Sendable, Equatable {
    let id: String

    /// Marketing name shown in UI, e.g. "Netflix"
    let displayName: String

    /// Substrings (lowercased) matched against `primaryProvider` / `providers` from the API
    let matchKeywords: [String]

    /// URL schemes to pass to `canOpenURL` (no `://`). Must be listed in Info.plist.
    let querySchemes: [String]

    /// If true, `titleAppURLTemplate` is used when non-nil; otherwise only home / search fallbacks apply.
    let supportsTitleDeepLink: Bool

    /// Optional app deep link with `{title}` placeholder (percent-encoded). Most providers do not expose stable title URLs.
    let titleAppURLTemplate: String?

    /// Deep link that opens the provider app to a sensible home / browse experience.
    let homeAppURL: URL

    /// Universal HTTPS URL (opens in-app browser or Safari; may hand off to app via Universal Links).
    let universalWebURL: URL

    /// App Store product page for the provider’s iOS app.
    let appStoreURL: URL

    /// Primary action label, e.g. "Open in Netflix"
    let primaryActionTitle: String

    /// Whether to show extra choices when title-level deep linking is not available.
    let offerWebAndSearchFallbacks: Bool

    static func == (lhs: StreamingProviderDefinition, rhs: StreamingProviderDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Catalog

enum StreamingProviderCatalog {
    /// Ordered: first keyword match wins; put more specific names before generic ones (e.g. "apple tv" before "tv").
    static let definitions: [StreamingProviderDefinition] = [
        StreamingProviderDefinition(
            id: "netflix",
            displayName: "Netflix",
            matchKeywords: ["netflix", "nflx"],
            querySchemes: ["nflx", "nfb"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "nflx://www.netflix.com/browse")!,
            universalWebURL: URL(string: "https://www.netflix.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/netflix/id363590051")!,
            primaryActionTitle: "Open in Netflix",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "max",
            displayName: "Max",
            matchKeywords: ["hbo max", "hbomax", "max", "hbo"],
            querySchemes: ["hbomax", "hmax"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "hbomax://")!,
            universalWebURL: URL(string: "https://www.max.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/max-stream-hbo-tv-movies/id1517513367")!,
            primaryActionTitle: "Watch on Max",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "disney",
            displayName: "Disney+",
            matchKeywords: ["disney", "disney+"],
            querySchemes: ["disneyplus"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "disneyplus://")!,
            universalWebURL: URL(string: "https://www.disneyplus.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/disney/id1446075923")!,
            primaryActionTitle: "Open in Disney+",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "prime",
            displayName: "Prime Video",
            matchKeywords: ["prime video", "prime", "amazon"],
            querySchemes: ["aiv", "amzn"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "aiv://")!,
            universalWebURL: URL(string: "https://www.amazon.com/gp/video/storefront")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/amazon-prime-video/id545519333")!,
            primaryActionTitle: "Open in Prime Video",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "hulu",
            displayName: "Hulu",
            matchKeywords: ["hulu"],
            querySchemes: ["hulu"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "hulu://")!,
            universalWebURL: URL(string: "https://www.hulu.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/hulu-watch-tv-shows-movies/id376510438")!,
            primaryActionTitle: "Open in Hulu",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "apple_tv",
            displayName: "Apple TV",
            matchKeywords: ["apple tv", "apple tv+"],
            querySchemes: ["com.apple.tv", "videos"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "com.apple.tv://")!,
            universalWebURL: URL(string: "https://tv.apple.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/apple-tv/id1174078549")!,
            primaryActionTitle: "Open in Apple TV",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "paramount",
            displayName: "Paramount+",
            matchKeywords: ["paramount", "paramount+"],
            querySchemes: ["paramountplus", "cbs"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "paramountplus://")!,
            universalWebURL: URL(string: "https://www.paramountplus.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/paramount/id1340650527")!,
            primaryActionTitle: "Open in Paramount+",
            offerWebAndSearchFallbacks: true
        ),
        StreamingProviderDefinition(
            id: "peacock",
            displayName: "Peacock",
            matchKeywords: ["peacock"],
            querySchemes: ["peacock"],
            supportsTitleDeepLink: false,
            titleAppURLTemplate: nil,
            homeAppURL: URL(string: "peacock://")!,
            universalWebURL: URL(string: "https://www.peacocktv.com")!,
            appStoreURL: URL(string: "https://apps.apple.com/app/peacock-tv/id1508186374")!,
            primaryActionTitle: "Open in Peacock",
            offerWebAndSearchFallbacks: true
        )
    ]

    /// Resolves a catalog entry from API provider string(s).
    static func definition(forPrimaryProvider primary: String?, providers: [String]?) -> StreamingProviderDefinition? {
        let candidates: [String] = {
            var list: [String] = []
            if let p = primary?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                list.append(p)
            }
            list.append(contentsOf: providers ?? [])
            return list
        }()
        for raw in candidates {
            let norm = normalize(raw)
            for def in definitions {
                for kw in def.matchKeywords {
                    if norm.contains(kw) { return def }
                }
            }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Launch outcomes

enum StreamingProviderLaunchResult: Equatable {
    case opened(URL)
    case failed(String)
}

// MARK: - Launcher (UIApplication)

enum StreamingProviderLauncher {

    /// Returns true if any registered scheme for this provider responds to `canOpenURL`.
    static func isAppInstalled(_ definition: StreamingProviderDefinition) -> Bool {
        for scheme in definition.querySchemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            if UIApplication.shared.canOpenURL(url) { return true }
        }
        return false
    }

    /// Preferred path: title deep link (if configured) → app home → universal web → App Store → web search.
    @MainActor
    static func open(for show: WatchShowItem) async -> StreamingProviderLaunchResult {
        guard let def = StreamingProviderCatalog.definition(
            forPrimaryProvider: show.primaryProvider,
            providers: show.providers
        ) else {
            return await openGenericWebSearch(title: show.title, providerLabel: show.primaryProvider)
        }

        if def.supportsTitleDeepLink, let template = def.titleAppURLTemplate {
            let encoded = show.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? show.title
            if let url = URL(string: template.replacingOccurrences(of: "{title}", with: encoded)) {
                let ok = await openURL(url)
                if ok { return .opened(url) }
            }
        }

        if isAppInstalled(def) {
            let ok = await openURL(def.homeAppURL)
            if ok { return .opened(def.homeAppURL) }
        }

        let webOk = await openURL(def.universalWebURL)
        if webOk { return .opened(def.universalWebURL) }

        let storeOk = await openURL(def.appStoreURL)
        if storeOk { return .opened(def.appStoreURL) }

        return await openGenericWebSearch(title: show.title, providerLabel: def.displayName)
    }

    /// Open provider website (HTTPS) in Safari / in-app browser.
    @MainActor
    static func openProviderWebsite(_ definition: StreamingProviderDefinition) async -> StreamingProviderLaunchResult {
        let ok = await openURL(definition.universalWebURL)
        return ok ? .opened(definition.universalWebURL) : .failed("Couldn’t open the website.")
    }

    /// Open App Store page for the provider app.
    @MainActor
    static func openAppStore(_ definition: StreamingProviderDefinition) async -> StreamingProviderLaunchResult {
        let ok = await openURL(definition.appStoreURL)
        return ok ? .opened(definition.appStoreURL) : .failed("Couldn’t open the App Store.")
    }

    /// Google search for “{title} {provider} watch”.
    @MainActor
    static func openGenericWebSearch(title: String, providerLabel: String?) async -> StreamingProviderLaunchResult {
        var parts = [title]
        if let p = providerLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            parts.append(p)
        }
        parts.append("watch")
        let q = parts.joined(separator: " ")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+=&")
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return .failed("Invalid search.")
        }
        let ok = await openURL(url)
        return ok ? .opened(url) : .failed("Couldn’t open search.")
    }

    @MainActor
    private static func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - SwiftUI controls

enum StreamingProviderLaunchButtonStyle {
    case heroPrimary
    case heroSecondary
    case cardCompact
}

/// Reusable control: tries provider-aware launch; unknown providers get “Find where to watch” web search.
struct StreamingProviderLaunchControl: View {
    let show: WatchShowItem
    var style: StreamingProviderLaunchButtonStyle = .heroPrimary

    @State private var isOpening = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if let def = StreamingProviderCatalog.definition(
                forPrimaryProvider: show.primaryProvider,
                providers: show.providers
            ) {
                if def.offerWebAndSearchFallbacks && !def.supportsTitleDeepLink {
                    Menu {
                        Button {
                            Task { await runOpen() }
                        } label: {
                            Label(def.primaryActionTitle, systemImage: "arrow.up.right.square")
                        }
                        Button {
                            Task { await runWebsite(def) }
                        } label: {
                            Label("Open \(def.displayName) website", systemImage: "safari")
                        }
                        Button {
                            Task { await runSearch() }
                        } label: {
                            Label("Search the web for “\(show.title)”", systemImage: "magnifyingglass")
                        }
                        if !StreamingProviderLauncher.isAppInstalled(def) {
                            Button {
                                Task { await runAppStore(def) }
                            } label: {
                                Label("Get \(def.displayName) in App Store", systemImage: "arrow.down.app")
                            }
                        }
                    } label: {
                        menuLabel(def.primaryActionTitle)
                    }
                    .disabled(isOpening)
                    .modifier(LaunchButtonProminenceModifier(style: style))
                } else {
                    Button {
                        Task { await runOpen() }
                    } label: {
                        menuLabel(def.primaryActionTitle)
                    }
                    .disabled(isOpening)
                    .modifier(LaunchButtonProminenceModifier(style: style))
                }
            } else {
                Button {
                    Task { await runSearch() }
                } label: {
                    menuLabel("Find where to watch")
                }
                .disabled(isOpening)
                .modifier(LaunchButtonProminenceModifier(style: style))
            }
        }
        .accessibilityHint("Opens the streaming app if installed, or offers web and App Store options.")
        .alert("Couldn’t open link", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String) -> some View {
        switch style {
        case .heroPrimary:
            Label(title, systemImage: "play.rectangle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        case .heroSecondary:
            Label(title, systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.semibold))
        case .cardCompact:
            Label(title, systemImage: "arrow.up.right.square")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

    @MainActor
    private func runOpen() async {
        isOpening = true
        AppHaptics.lightImpact()
        let r = await StreamingProviderLauncher.open(for: show)
        handle(r)
        isOpening = false
    }

    @MainActor
    private func runWebsite(_ def: StreamingProviderDefinition) async {
        isOpening = true
        AppHaptics.lightImpact()
        let r = await StreamingProviderLauncher.openProviderWebsite(def)
        handle(r)
        isOpening = false
    }

    @MainActor
    private func runAppStore(_ def: StreamingProviderDefinition) async {
        isOpening = true
        AppHaptics.lightImpact()
        let r = await StreamingProviderLauncher.openAppStore(def)
        handle(r)
        isOpening = false
    }

    @MainActor
    private func runSearch() async {
        isOpening = true
        AppHaptics.lightImpact()
        let r = await StreamingProviderLauncher.openGenericWebSearch(
            title: show.title,
            providerLabel: show.primaryProvider
        )
        handle(r)
        isOpening = false
    }

    private func handle(_ result: StreamingProviderLaunchResult) {
        switch result {
        case .opened:
            AppHaptics.selection()
        case .failed(let msg):
            errorMessage = msg
            showErrorAlert = true
        }
    }
}

private struct LaunchButtonProminenceModifier: ViewModifier {
    let style: StreamingProviderLaunchButtonStyle

    func body(content: Content) -> some View {
        switch style {
        case .heroPrimary:
            content
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .heroSecondary:
            content
                .buttonStyle(.bordered)
        case .cardCompact:
            content
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
