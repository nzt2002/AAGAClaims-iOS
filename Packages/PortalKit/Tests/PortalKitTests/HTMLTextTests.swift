import Foundation
import Testing
@testable import PortalKit

@Suite("HTMLText")
struct HTMLTextTests {
    @Test("Strips tags and decodes entities")
    func basic() {
        #expect(HTMLText.plainText("<p>Hello <strong>Alex</strong> &amp; family</p>") == "Hello Alex & family")
    }

    @Test("Removes scripts, styles and iframes with their contents")
    func scripts() {
        let html = "<p>Safe</p><script>alert('x')</script><style>p{}</style><iframe src=\"https://evil\">x</iframe><p>Text</p>"
        #expect(HTMLText.plainText(html) == "Safe\n\nText")
    }

    @Test("Paragraphs and breaks become lines")
    func lines() {
        #expect(HTMLText.plainText("<p>One</p><p>Two<br/>Three</p>") == "One\n\nTwo\nThree")
    }

    @Test("Nil and empty are empty")
    func empty() {
        #expect(HTMLText.plainText(nil).isEmpty)
        #expect(HTMLText.plainText("").isEmpty)
    }

    @Test("Bold and italic become presentation intents")
    func emphasis() throws {
        let text = HTMLText.attributed("<p>Plain <b>bold</b> <em>soft</em></p>")
        let bold = try #require(text.range(of: "bold"))
        let soft = try #require(text.range(of: "soft"))
        #expect(text[bold].inlinePresentationIntent == .stronglyEmphasized)
        #expect(text[soft].inlinePresentationIntent == .emphasized)
    }

    @Test("Safe links are kept; javascript and data links are dropped")
    func links() throws {
        let text = HTMLText.attributed(
            #"<a href="https://example.com/a?x=1&amp;y=2">ok</a> <a href="javascript:alert(1)">bad</a> <a href='mailto:sam@example.com'>mail</a>"#
        )
        let ok = try #require(text.range(of: "ok"))
        let bad = try #require(text.range(of: "bad"))
        let mail = try #require(text.range(of: "mail"))
        #expect(text[ok].link == URL(string: "https://example.com/a?x=1&y=2"))
        #expect(text[bad].link == nil)
        #expect(text[mail].link == URL(string: "mailto:sam@example.com"))
    }

    @Test("Lists get bullets and numbers")
    func lists() {
        #expect(HTMLText.plainText("<ul><li>Roof</li><li>Gutters</li></ul>") == "• Roof\n• Gutters")
        #expect(HTMLText.plainText("<p>Steps</p><ol><li>File</li><li>Inspect</li></ol>") == "Steps\n\n1. File\n2. Inspect")
    }

    @Test("Numeric entities and whitespace")
    func entities() {
        #expect(HTMLText.plainText("<p>It&#39;s   <b>done</b>&#x21;</p>") == "It's done!")
    }
}
