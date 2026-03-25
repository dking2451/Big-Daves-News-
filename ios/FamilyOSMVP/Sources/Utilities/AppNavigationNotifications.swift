import Foundation

extension Notification.Name {
    /// Posted after extracted events are saved so the main tab bar can switch to Home.
    static let familyOSNavigateToHome = Notification.Name("familyOSNavigateToHome")
}
