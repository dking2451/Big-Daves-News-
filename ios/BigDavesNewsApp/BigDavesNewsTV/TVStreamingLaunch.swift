import UIKit

struct TVProviderDefinition: Identifiable, Sendable {
    let id: String
    let displayName: String
    let matchKeywords: [String]
    let querySchemes: [String]
    let homeAppURL: URL
    let universalWebURL: URL
    let primaryActionTitle: String
}

enum TVProviderCatalog {
    static let all: [TVProviderDefinition] = [
        TVProviderDefinition(
            id: "netflix", displayName: "Netflix", matchKeywords: ["netflix", "nflx"],
            querySchemes: ["nflx", "nfb"], homeAppURL: URL(string: "nflx://www.netflix.com/browse")!,
            universalWebURL: URL(string: "https://www.netflix.com")!, primaryActionTitle: "Open in Netflix"
        ),
        TVProviderDefinition(
            id: "max", displayName: "HBO Max", matchKeywords: ["hbo max", "hbomax", "max", "hbo"],
            querySchemes: ["hbomax", "hmax"], homeAppURL: URL(string: "hbomax://")!,
            universalWebURL: URL(string: "https://www.max.com")!, primaryActionTitle: "Open in HBO Max"
        ),
        TVProviderDefinition(
            id: "disney", displayName: "Disney+", matchKeywords: ["disney", "disney+"],
            querySchemes: ["disneyplus"], homeAppURL: URL(string: "disneyplus://")!,
            universalWebURL: URL(string: "https://www.disneyplus.com")!, primaryActionTitle: "Open in Disney+"
        ),
        TVProviderDefinition(
            id: "prime", displayName: "Prime Video", matchKeywords: ["prime video", "prime", "amazon"],
            querySchemes: ["aiv", "amzn"], homeAppURL: URL(string: "aiv://")!,
            universalWebURL: URL(string: "https://www.amazon.com/gp/video/storefront")!, primaryActionTitle: "Open in Prime Video"
        ),
        TVProviderDefinition(
            id: "hulu", displayName: "Hulu", matchKeywords: ["hulu"],
            querySchemes: ["hulu"], homeAppURL: URL(string: "hulu://")!,
            universalWebURL: URL(string: "https://www.hulu.com")!, primaryActionTitle: "Open in Hulu"
        ),
        TVProviderDefinition(
            id: "apple_tv", displayName: "Apple TV", matchKeywords: ["apple tv", "apple tv+"],
            querySchemes: ["com.apple.tv", "videos"], homeAppURL: URL(string: "com.apple.tv://")!,
            universalWebURL: URL(string: "https://tv.apple.com")!, primaryActionTitle: "Open in Apple TV"
        ),
        TVProviderDefinition(
            id: "paramount", displayName: "Paramount+", matchKeywords: ["paramount", "paramount+"],
            querySchemes: ["paramountplus", "cbs"], homeAppURL: URL(string: "paramountplus://")!,
            universalWebURL: URL(string: "https://www.paramountplus.com")!, primaryActionTitle: "Open in Paramount+"
        ),
        TVProviderDefinition(
            id: "peacock", displayName: "Peacock", matchKeywords: ["peacock"],
            querySchemes: ["peacock"], homeAppURL: URL(string: "peacock://")!,
            universalWebURL: URL(string: "https://www.peacocktv.com")!, primaryActionTitle: "Open in Peacock"
        ),
    ]

    static func definition(primary: String?, providers: [String]?) -> TVProviderDefinition? {
        var list: [String] = []
        if let p = primary?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { list.append(p) }
        list.append(contentsOf: providers ?? [])
        for raw in list {
            let norm = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for def in all {
                for kw in def.matchKeywords where norm.contains(kw) { return def }
            }
        }
        return nil
    }

    static func canOpen(_ def: TVProviderDefinition) -> Bool {
        for scheme in def.querySchemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            if UIApplication.shared.canOpenURL(url) { return true }
        }
        return false
    }

    @MainActor
    static func open(_ show: TVWatchShowItem) async -> Bool {
        guard let def = definition(primary: show.primaryProvider, providers: show.providers) else {
            return await openURL(URL(string: "https://www.google.com/search?q=\((show.title + " watch").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!)
        }
        if canOpen(def), await openURL(def.homeAppURL) { return true }
        return await openURL(def.universalWebURL)
    }

    @MainActor
    private static func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { cont in
            UIApplication.shared.open(url, options: [:]) { cont.resume(returning: $0) }
        }
    }
}
