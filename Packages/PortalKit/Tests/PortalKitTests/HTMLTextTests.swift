import Testing
@testable import PortalKit

@Suite("HTMLText")
struct HTMLTextTests {
    @Test("Strips tags and decodes entities")
    func basic() {
        #expect(HTMLText.plainText("<p>Hello <strong>Alex</strong> &amp; family</p>") == "Hello Alex & family")
    }

    @Test("Removes scripts and styles with their contents")
    func scripts() {
        let html = "<p>Safe</p><script>alert('x')</script><style>p{}</style><p>Text</p>"
        #expect(HTMLText.plainText(html) == "Safe\nText")
    }

    @Test("Paragraphs and breaks become lines")
    func lines() {
        #expect(HTMLText.plainText("<p>One</p><p>Two<br/>Three</p>") == "One\nTwo\nThree")
    }

    @Test("Nil and empty are empty")
    func empty() {
        #expect(HTMLText.plainText(nil).isEmpty)
        #expect(HTMLText.plainText("").isEmpty)
    }
}
