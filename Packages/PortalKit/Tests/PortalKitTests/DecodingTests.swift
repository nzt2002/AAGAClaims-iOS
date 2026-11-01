import Foundation
import Testing
@testable import PortalKit

@Suite("JSON decoding")
struct DecodingTests {
    @Test("A post with a file Chatter can't identify still decodes, without that file")
    func postWithUnidentifiedFile() throws {
        // The live feed of a claim with a deleted file (2026-10-31): the whole Chatter feed failed to load.
        let json = #"""
        [{"totalReplies":0,"text":"File Upload","replies":[{"text":"Hi","mentions":[],"isMine":true,"id":"0D7000000000001AAA",
          "createdDate":"2026-10-19T17:48:03.000Z","authorName":"Pat","attachments":[{"title":null,"id":null}]}],
          "parentName":null,"mentions":[],"id":"0D5Rh00001944MDKAY","createdDate":"2026-07-29T02:14:53.000Z",
          "authorName":"ProClaimer Support","attachments":[{"title":null,"id":null,"fileType":"Unknown","fileExtension":null,"contentSize":null},
          {"title":"Roof.jpg","id":"069000000000001AAA","fileType":"JPG","fileExtension":"jpg","contentSize":10}]}]
        """#
        let posts = try PortalJSON.makeDecoder().decode([ChatterPost].self, from: Data(json.utf8))
        #expect(posts.first?.attachments?.map(\.id) == ["069000000000001AAA"])
        #expect(posts.first?.replies.first?.attachments?.isEmpty == true)
        #expect(posts.first?.authorName == "ProClaimer Support")
    }

    @Test("All bundled fixtures decode")
    func bundledFixturesDecode() throws {
        let fixtures = try MockPortalAPI.Fixtures.bundled()
        #expect(fixtures.claims.count == 4)
        #expect(fixtures.leads.count == 3)
        #expect(fixtures.cases.count == 2)
    }

    @Test("Spec §5.1 claim example decodes, with and without milliseconds")
    func specClaimExample() throws {
        let json = """
        {
          "recordId": "a0X...", "recordName": "Smith - Roof", "claimNumber": "CLM-1234",
          "policyNumber": "POL-5678", "claimStatus": "Inspection", "peril": "Wind",
          "lossAddress": "123 Main St, Atlanta, GA 30301", "lossDate": "2026-08-14",
          "lossReason": "Storm", "paymentCollected": 12500.00,
          "adjusterName": "Jane Doe", "accountManagerName": "Sam Lee",
          "lastModifiedDate": "2026-10-01T14:22:00Z"
        }
        """
        let claim = try PortalJSON.makeDecoder().decode(ClaimSummary.self, from: Data(json.utf8))
        #expect(claim.lossDate == CalendarDate(year: 2026, month: 8, day: 14))
        #expect(claim.paymentCollected == Decimal(12_500))

        let apexStyle = json.replacingOccurrences(of: "14:22:00Z", with: "14:22:00.000Z")
        let fromApex = try PortalJSON.makeDecoder().decode(ClaimSummary.self, from: Data(apexStyle.utf8))
        #expect(fromApex.lastModifiedDate == claim.lastModifiedDate)
    }

    @Test("Missing optional fields decode as nil")
    func sparseClaim() throws {
        let json = #"{ "recordId": "a0X1" }"#
        let claim = try PortalJSON.makeDecoder().decode(ClaimSummary.self, from: Data(json.utf8))
        #expect(claim.recordName == nil)
        #expect(claim.lifecycle == .unknown(nil))
    }

    @Test("relatedRecordType 'Prospect' is a lead")
    func prospectIsLead() throws {
        let fixtures = try MockPortalAPI.Fixtures.bundled()
        let leadItem = try #require(fixtures.activity.first { $0.relatedRecordType == .prospect })
        #expect(leadItem.recordRef == .lead(leadItem.relatedRecordId))
        #expect(RelatedRecordType.prospect.displayName == "Lead")
    }

    @Test("Agreement status COMPLETE means signed")
    func agreementSigned() throws {
        let fixtures = try MockPortalAPI.Fixtures.bundled()
        let signed = try #require(fixtures.leadDetails["a0r000000000002AAA"]?.agreement)
        let sent = try #require(fixtures.leadDetails["a0r000000000001AAA"]?.agreement)
        #expect(signed.isSigned)
        #expect(!sent.isSigned)
        #expect(sent.viewedDate == nil)
    }

    @Test("CalendarDate round-trips and ignores time zones")
    func calendarDate() throws {
        let date = try #require(CalendarDate(string: "2026-08-14"))
        #expect(date.description == "2026-08-14")
        let encoded = try PortalJSON.makeEncoder().encode([date])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["2026-08-14"]"#)
        #expect(CalendarDate(string: "garbage") == nil)
    }
}
