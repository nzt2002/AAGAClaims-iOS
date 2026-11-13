import Foundation

/// Why a business-line call didn't start or dropped, in words staff can act on. The app used to
/// end such calls silently, which left nothing to go on (3.9.2). Each message ends with the
/// underlying code so support can match it to the server or Twilio logs.
public struct CallFailure: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    /// The microphone is off for the app, so iOS won't let it place calls.
    public static let microphoneDenied = CallFailure(
        title: "Microphone is off",
        message: "Turn on Microphone for ProClaimer in Settings › Privacy & Security › Microphone, then try the call again."
    )

    /// `GET /voice/token` failed: the app couldn't get permission from the server to place the call.
    public static func token(_ error: Error) -> CallFailure {
        let title = "Couldn't start the call"
        switch error as? PortalAPIError {
        case .sessionExpired?:
            return CallFailure(title: title, message: "Your sign-in has expired. Sign out and back in, then try again. (token 401)")
        case .notFound?:
            return CallFailure(title: title, message: "Business-line calling isn't set up for your account: you need a Calling seat and your own business line. Ask your administrator. (token 404)")
        case .offline?:
            return CallFailure(title: title, message: "You're offline. Check your connection and try again. (token offline)")
        case .server(let status)?:
            return CallFailure(title: title, message: "The server had a problem. Try again in a moment. (token \(status))")
        case let other?:
            return CallFailure(title: title, message: "Try again in a moment. (token \(other))")
        case nil:
            return CallFailure(title: title, message: "Try again in a moment. (token: \(error.localizedDescription))")
        }
    }

    /// Twilio reported an error. `connected` is false when the call never got through.
    public static func twilio(code: Int, description: String, connected: Bool) -> CallFailure {
        let title = connected ? "Call dropped" : "Call didn't connect"
        let advice: String
        switch code {
        case 20101, 20104, 20157:
            advice = "The call permission expired. Close and reopen the app, then try again."
        case 31005, 31009, 53000, 53001, 53405:
            advice = "The connection to the phone service was lost. Check your signal or Wi-Fi and try again."
        case 31208, 31401, 31402:
            advice = "The app couldn't use the microphone. Check Settings › Privacy & Security › Microphone."
        case 31480, 31486:
            advice = "The number is busy or unavailable. Try again later."
        case 31603:
            advice = "The call was declined."
        default:
            advice = "Try again. If it keeps happening, send this message to support."
        }
        let detail = description.isEmpty ? "" : " \(description)"
        return CallFailure(title: title, message: "\(advice) (Twilio \(code)\(detail))")
    }

    /// iOS refused to start the call (e.g. another call is in progress).
    public static func callKit(_ description: String) -> CallFailure {
        CallFailure(title: "Couldn't start the call", message: "iPhone wouldn't start the call: \(description)")
    }
}
