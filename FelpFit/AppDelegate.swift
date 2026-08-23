import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = UIColor(red: 9 / 255, green: 9 / 255, blue: 14 / 255, alpha: 1)
        window.rootViewController = FelpFitViewController()
        window.makeKeyAndVisible()
        self.window = window
        FelpFitPushCoordinator.shared.configure(application: application)
        if let url = launchOptions?[.url] as? URL, url.scheme?.lowercased() == "felpfit" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .felpFitDeepLinkReceived,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        FelpFitPushCoordinator.shared.didRegister(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        FelpFitPushCoordinator.shared.didFailToRegister(error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        FelpFitPushCoordinator.shared.handleRemoteNotification(userInfo)
        completionHandler(.newData)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.scheme?.lowercased() == "felpfit" else { return false }
        NotificationCenter.default.post(
            name: .felpFitDeepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
        return true
    }
}

