import SalesforceSDKCore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    override init() {
        super.init()
        if AppEnvironment.current.auth == .salesforce {
            SalesforceManager.initializeSDK()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
