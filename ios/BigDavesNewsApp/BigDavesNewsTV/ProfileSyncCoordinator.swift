import Foundation
import SwiftUI

/// Local cache of the composed profile; server is authoritative after refresh.
@MainActor
final class ProfileSyncCoordinator: ObservableObject {
    static let shared = ProfileSyncCoordinator()

    private static let cacheKey = "bdn-tv-profile-cache-v1"

    @Published private(set) var profile: ComposedUserProfile?
    @Published private(set) var lastError: String?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let c = try? JSONDecoder().decode(ComposedUserProfile.self, from: data) {
            profile = c
        }
    }

    func loadCached() -> ComposedUserProfile? { profile }

    func refreshFromServer() async {
        let uid = SyncedUserIdentity.apiUserKey
        do {
            let p = try await TVAPIClient.shared.fetchProfile(userId: uid)
            profile = p
            if let data = try? JSONEncoder().encode(p) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    /// Optimistic local merge + async PATCH; refreshes profile when done.
    func applyWatchPatch(watchPatch: [String: Any]) {
        Task { await applyWatchPatchSync(watchPatch: watchPatch) }
    }

    /// Merge into cached profile immediately (MainActor). Does not hit the network.
    func applyWatchPatchLocally(watchPatch: [String: Any]) {
        var base = profile ?? ComposedUserProfile()
        var w = base.watch ?? ProfileWatchBlock()
        if let ids = watchPatch["saved_show_ids"] as? [String] {
            w.savedShowIds = ids
        }
        if let states = watchPatch["watch_state_by_show"] as? [String: String] {
            var m = w.watchStateByShow ?? [:]
            for (k, v) in states { m[k] = v }
            w.watchStateByShow = m
        }
        base.watch = w
        profile = base
        if let data = try? JSONEncoder().encode(base) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    func applyWatchPatchSyncNetworkOnly(watchPatch: [String: Any]) async {
        let uid = SyncedUserIdentity.apiUserKey
        do {
            let p = try await TVAPIClient.shared.patchProfile(userId: uid, patch: ["watch": watchPatch])
            await MainActor.run {
                profile = p
                if let data = try? JSONEncoder().encode(p) {
                    UserDefaults.standard.set(data, forKey: Self.cacheKey)
                }
                lastError = nil
            }
        } catch {
            await MainActor.run { lastError = (error as NSError).localizedDescription }
            await refreshFromServer()
        }
    }

    /// Local merge (immediate cache) then PATCH.
    func applyWatchPatchSync(watchPatch: [String: Any]) async {
        applyWatchPatchLocally(watchPatch: watchPatch)
        await applyWatchPatchSyncNetworkOnly(watchPatch: watchPatch)
    }

    func applyPreferencesPatch(_ prefs: [String: Any]) {
        Task {
            let uid = SyncedUserIdentity.apiUserKey
            do {
                let p = try await TVAPIClient.shared.patchProfile(userId: uid, patch: ["preferences": prefs])
                await MainActor.run {
                    self.profile = p
                    if let data = try? JSONEncoder().encode(p) {
                        UserDefaults.standard.set(data, forKey: Self.cacheKey)
                    }
                }
            } catch {
                await MainActor.run { self.lastError = (error as NSError).localizedDescription }
            }
        }
    }
}
