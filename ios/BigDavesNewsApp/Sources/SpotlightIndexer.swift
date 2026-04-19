#if os(iOS)
import CoreSpotlight
import Foundation
import MobileCoreServices

/// Indexes headlines and watch shows in iOS Spotlight so users can find
/// content directly from the home screen search.
enum SpotlightIndexer {
    static let headlineDomain = "com.bigdavesnews.app.headline"
    static let showDomain     = "com.bigdavesnews.app.show"

    /// User-activity type used for Spotlight deep-link callbacks.
    static let activityTypeHeadline = "com.bigdavesnews.app.headline"
    static let activityTypeShow     = "com.bigdavesnews.app.show"

    // MARK: - Index headlines

    static func indexClaims(_ claims: [Claim]) async {
        let items: [CSSearchableItem] = claims.map { claim in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = claim.text
            attrs.contentDescription = "\(claim.category) · \(claim.status.capitalized)"
            attrs.keywords = [claim.category, claim.subtopic, "news", "headline", "fact check"]
            attrs.domainIdentifier = headlineDomain

            return CSSearchableItem(
                uniqueIdentifier: "headline-\(claim.claimID)",
                domainIdentifier: headlineDomain,
                attributeSet: attrs
            )
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CSSearchableIndex.default().indexSearchableItems(items) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Index watch shows

    static func indexShows(_ shows: [WatchShowItem]) async {
        // Limit to the top 50 to avoid flooding the Spotlight index.
        let items: [CSSearchableItem] = shows.prefix(50).map { show in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = show.title
            attrs.contentDescription = show.synopsis
            attrs.keywords = show.genres + show.providers + ["watch", "streaming", "show", "movie"]
            attrs.domainIdentifier = showDomain

            // Use a poster thumbnail when it's trusted art.
            if let url = show.posterRemoteImageURL {
                attrs.thumbnailURL = url
            }

            return CSSearchableItem(
                uniqueIdentifier: "show-\(show.id)",
                domainIdentifier: showDomain,
                attributeSet: attrs
            )
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CSSearchableIndex.default().indexSearchableItems(items) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Deep-link resolution

    /// Returns the AppTab to navigate to when a Spotlight result is tapped.
    /// The uniqueIdentifier from CSSearchableItemActivityIdentifier drives the decision.
    static func resolveTab(from uniqueIdentifier: String) -> AppTab {
        if uniqueIdentifier.hasPrefix("show-") { return .watch }
        return .headlines
    }

    // MARK: - Cleanup

    static func clearAll() {
        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
    }
}

#endif
