import PortalKit
import UIKit

/// Gets this phone's Apple push address to the ProClaimer platform, which sends the alerts (the Salesforce build uses the
/// Mobile SDK instead and never touches this). The address can arrive before the person is signed in, and sign-in can
/// happen before the address arrives, so it's kept here and sent as soon as both are known.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private var token: String?
    private var api: PortalAPI?
    private var sent: String?

    /// "sandbox" when run from Xcode, "production" for TestFlight and the App Store
    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Apple handed over the device token
    func received(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        Task { await sync() }
    }

    /// Someone is signed in and the API is ready
    func attach(api: PortalAPI) {
        self.api = api
        Task { await sync() }
    }

    private func sync() async {
        guard let token, let api, sent != token else { return }
        // Push is optional: a failed registration is simply tried again next launch
        if (try? await api.registerPushDevice(token: token, environment: environment)) != nil { sent = token }
    }

    /// Sign-out: this phone shouldn't get the previous person's alerts
    func unregister() async {
        guard let token, let api else { return }
        try? await api.unregisterPushDevice(token: token)
        sent = nil
        self.api = nil
    }
}
