import Foundation

enum SportsProviderPreferences {
    static let providerKeyStorageKey = "bdn-sports-provider-key-ios"
    static let availabilityOnlyStorageKey = "bdn-sports-availability-only-ios"

    static let allProviderKey = "all"

    static let options: [(key: String, label: String)] = [
        (allProviderKey, "All Providers"),
        ("youtube_tv", "YouTube TV"),
        ("hulu_live", "Hulu + Live TV"),
        ("fubo", "Fubo"),
        ("xfinity", "Xfinity"),
        ("directv_stream", "DIRECTV STREAM"),
        ("sling", "Sling TV"),
    ]

    static func label(for key: String) -> String {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return options.first(where: { $0.key == normalized })?.label ?? "All Providers"
    }

    static func normalizedProviderKey(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if options.contains(where: { $0.key == normalized }) {
            return normalized
        }
        return allProviderKey
    }

    static var backendProviderKeyFromDefaults: String {
        let stored = UserDefaults.standard.string(forKey: providerKeyStorageKey) ?? allProviderKey
        let normalized = normalizedProviderKey(stored)
        if normalized == allProviderKey {
            return ""
        }
        return normalized
    }
}
