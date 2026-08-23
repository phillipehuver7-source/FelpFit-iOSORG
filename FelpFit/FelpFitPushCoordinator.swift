import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let felpFitRemotePushStateDidChange = Notification.Name("felpfit.remotePush.stateDidChange")
    static let felpFitRemoteNotificationReceived = Notification.Name("felpfit.remotePush.received")
    static let felpFitDeepLinkReceived = Notification.Name("felpfit.deepLink.received")
}

/// Owns the APNs registration lifecycle. Delivery to the FelpFit backend is
/// performed by the authenticated web layer so the native shell never copies
/// or persists the user's web credentials.
final class FelpFitPushCoordinator {
    static let shared = FelpFitPushCoordinator()

    private enum DefaultsKey {
        static let lastRegistrationError = "felpfit.remotePush.lastRegistrationError.v1"
        static let lastTokenReceivedAt = "felpfit.remotePush.lastTokenReceivedAt.v1"
    }

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var deviceToken: String?

    private init() {}

    func configure(application: UIApplication) {
        registerNotificationCategories()
        application.registerForRemoteNotifications()
    }

    func retryRegistration(application: UIApplication = .shared) {
        application.registerForRemoteNotifications()
    }

    func didRegister(deviceToken data: Data) {
        // Apple documents device tokens as variable-length opaque data. Convert
        // every byte without assuming a fixed token size and do not persist it.
        let token = data.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        deviceToken = token
        lock.unlock()

        defaults.removeObject(forKey: DefaultsKey.lastRegistrationError)
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastTokenReceivedAt)
        postStateChange()
    }

    func didFailToRegister(error: Error) {
        defaults.set(String(describing: error), forKey: DefaultsKey.lastRegistrationError)
        postStateChange()
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        NotificationCenter.default.post(
            name: .felpFitRemoteNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }

    func stateDictionary() -> [String: Any] {
        lock.lock()
        let token = deviceToken
        lock.unlock()

        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var result: [String: Any] = [
            "type": "remotePush",
            "supported": true,
            "registeredWithAPNs": token != nil,
            "deviceToken": token ?? "",
            "environment": Self.apnsEnvironment(),
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "app.felpfit.ios",
            "nativeBuild": build,
            "nativeVersion": version
        ]

        if let error = defaults.string(forKey: DefaultsKey.lastRegistrationError), !error.isEmpty {
            result["registrationError"] = error
        }
        let receivedAt = defaults.double(forKey: DefaultsKey.lastTokenReceivedAt)
        if receivedAt > 0 { result["tokenReceivedAt"] = receivedAt * 1000 }
        return result
    }

    private func postStateChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .felpFitRemotePushStateDidChange, object: nil)
        }
    }

    private func registerNotificationCategories() {
        let open = UNNotificationAction(
            identifier: "FELPFIT_OPEN",
            title: "Abrir FelpFit",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: "FELPFIT_SNOOZE_10",
            title: "Lembrar em 10 min",
            options: []
        )
        let update = UNNotificationCategory(
            identifier: "FELPFIT_UPDATE",
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        let reminder = UNNotificationCategory(
            identifier: "FELPFIT_REMINDER",
            actions: [open, snooze],
            intentIdentifiers: [],
            options: []
        )
        let hydration = UNNotificationCategory(
            identifier: "FELPFIT_HYDRATION",
            actions: [open, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([update, reminder, hydration])
    }

    private static func apnsEnvironment() -> String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}
