import Foundation
import UIKit

@MainActor
final class PushTokenManager: ObservableObject {
    static let shared = PushTokenManager()

    @Published var deviceToken: String = UserDefaults.standard.string(forKey: "bdn-apns-device-token-ios") ?? ""
    @Published var syncStatus: String = UserDefaults.standard.string(forKey: "bdn-apns-sync-status-ios") ?? "Not synced yet."

    private init() {}

    func requestSystemTokenRegistration() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleRegisteredDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        guard !token.isEmpty else {
            syncStatus = "Device token was empty."
            persist()
            return
        }
        deviceToken = token
        syncStatus = "APNs token received."
        persist()
        await registerWithBackendIfPossible()
    }

    func handleRegistrationFailure(_ error: Error) {
        syncStatus = "APNs registration failed: \(error.localizedDescription)"
        persist()
    }

    func registerWithBackendIfPossible() async {
        let token = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            syncStatus = "Waiting for APNs device token."
            persist()
            return
        }

        let email = UserDefaults.standard.string(forKey: "bdn-subscriber-email-ios") ?? ""
        do {
            let response = try await APIClient.shared.registerPushToken(
                token: token,
                subscriberEmail: email
            )
            syncStatus = response.message
            persist()
        } catch {
            syncStatus = "Backend token sync failed: \(error.localizedDescription)"
            persist()
        }
    }

    func unregisterFromBackendIfPossible() async {
        let token = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            syncStatus = "No APNs token to unregister."
            persist()
            return
        }
        do {
            let response = try await APIClient.shared.unregisterPushToken(token: token)
            syncStatus = response.message
            persist()
        } catch {
            syncStatus = "Backend unregister failed: \(error.localizedDescription)"
            persist()
        }
    }

    private func persist() {
        UserDefaults.standard.set(deviceToken, forKey: "bdn-apns-device-token-ios")
        UserDefaults.standard.set(syncStatus, forKey: "bdn-apns-sync-status-ios")
    }
}
