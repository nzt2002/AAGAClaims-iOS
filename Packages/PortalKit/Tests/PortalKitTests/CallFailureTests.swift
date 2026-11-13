import Foundation
import Testing
@testable import PortalKit

@Suite struct CallFailureTests {
    @Test func tokenErrorsSayWhatToDo() {
        #expect(CallFailure.token(PortalAPIError.sessionExpired).message.contains("Sign out and back in"))
        #expect(CallFailure.token(PortalAPIError.notFound).message.contains("own business line"))
        #expect(CallFailure.token(PortalAPIError.offline).message.contains("offline"))
        #expect(CallFailure.token(PortalAPIError.server(status: 500)).message.hasSuffix("(token 500)"))
        let other = CallFailure.token(URLError(.timedOut))
        #expect(other.title == "Couldn't start the call")
        #expect(other.message.contains("token:"))
    }

    @Test func twilioErrorsKeepTheCode() {
        let lost = CallFailure.twilio(code: 31005, description: "Connection error", connected: false)
        #expect(lost.title == "Call didn't connect")
        #expect(lost.message.contains("connection to the phone service"))
        #expect(lost.message.hasSuffix("(Twilio 31005 Connection error)"))

        let expired = CallFailure.twilio(code: 20104, description: "", connected: false)
        #expect(expired.message.contains("reopen the app"))
        #expect(expired.message.hasSuffix("(Twilio 20104)"))

        #expect(CallFailure.twilio(code: 31486, description: "Busy", connected: false).message.contains("busy"))
        #expect(CallFailure.twilio(code: 99999, description: "x", connected: true).title == "Call dropped")
    }
}
