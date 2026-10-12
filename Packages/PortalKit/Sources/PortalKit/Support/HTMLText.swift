import Foundation

/// Renders update bodies, which are HTML (spec §3), without WebKit.
///
/// `NSAttributedString`'s HTML importer runs WebKit and can fetch remote images, so instead this
/// keeps an allow-list: paragraphs, line breaks, lists, headings, bold, italic and links with
/// http(s), mailto or tel URLs. Scripts, styles and embedded content are dropped with their
/// contents; any other tag is dropped and its text kept.
public enum HTMLText {
    public static func attributed(_ html: String?) -> AttributedString {
        guard let html, !html.isEmpty else { return AttributedString() }
        var renderer = Renderer()
        renderer.render(stripDroppedElements(html))
        return renderer.output
    }

    public static func plainText(_ html: String?) -> String {
        String(attributed(html).characters)
    }

    // MARK: - Internals

    private static let droppedElements = ["script", "style", "iframe", "object", "embed", "noscript", "template", "head", "svg"]
    private static let blockElements: Set<String> = [
        "p", "div", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "tr", "table", "section"
    ]
    private static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    private static func stripDroppedElements(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        for tag in droppedElements {
            text = text.replacingOccurrences(
                of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            // Unclosed or self-closing leftovers.
            text = text.replacingOccurrences(
                of: "<\(tag)\\b[^>]*>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return text
    }

    private struct Renderer {
        var output = AttributedString()
        private var boldDepth = 0
        private var italicDepth = 0
        private var links: [URL?] = []
        private var listStack: [(ordered: Bool, index: Int)] = []
        private var pendingBreaks = 0
        private var atLineStart = true

        mutating func render(_ html: String) {
            let tagPattern = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/
            var cursor = html.startIndex
            for match in html.matches(of: tagPattern) {
                appendText(String(html[cursor..<match.range.lowerBound]))
                handleTag(
                    name: match.output.2.lowercased(),
                    isClosing: !match.output.1.isEmpty,
                    attributes: String(match.output.3)
                )
                cursor = match.range.upperBound
            }
            appendText(String(html[cursor...]))
        }

        private mutating func handleTag(name: String, isClosing: Bool, attributes: String) {
            switch name {
            case "br":
                lineBreak(1)
            case "b", "strong":
                boldDepth = max(0, boldDepth + (isClosing ? -1 : 1))
            case "i", "em":
                italicDepth = max(0, italicDepth + (isClosing ? -1 : 1))
            case "a":
                if isClosing {
                    _ = links.popLast()
                } else {
                    links.append(Self.safeURL(fromAttributes: attributes))
                }
            case "ul", "ol":
                if isClosing {
                    _ = listStack.popLast()
                } else {
                    listStack.append((ordered: name == "ol", index: 0))
                }
                lineBreak(1)
            case "li":
                lineBreak(1)
                if !isClosing, !listStack.isEmpty {
                    listStack[listStack.count - 1].index += 1
                    let item = listStack[listStack.count - 1]
                    let indent = String(repeating: "  ", count: listStack.count - 1)
                    appendRaw(indent + (item.ordered ? "\(item.index). " : "• "))
                }
            case "h1", "h2", "h3", "h4", "h5", "h6":
                boldDepth = max(0, boldDepth + (isClosing ? -1 : 1))
                lineBreak(2)
            default:
                if HTMLText.blockElements.contains(name) {
                    lineBreak(2)
                }
            }
        }

        private mutating func lineBreak(_ count: Int) {
            guard !output.characters.isEmpty else { return }
            pendingBreaks = max(pendingBreaks, count)
        }

        private mutating func appendText(_ raw: String) {
            var text = HTMLText.decodeEntities(raw)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if atLineStart || pendingBreaks > 0 {
                text = String(text.drop(while: { $0 == " " }))
            }
            guard !text.isEmpty else { return }
            appendRaw(text)
        }

        private mutating func appendRaw(_ text: String) {
            if pendingBreaks > 0 {
                output.append(AttributedString(String(repeating: "\n", count: pendingBreaks)))
                pendingBreaks = 0
            }
            var piece = AttributedString(text)
            var intent: InlinePresentationIntent = []
            if boldDepth > 0 { intent.insert(.stronglyEmphasized) }
            if italicDepth > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link = links.last, let url = link { piece.link = url }
            output.append(piece)
            atLineStart = false
        }

        private static func safeURL(fromAttributes attributes: String) -> URL? {
            let hrefPattern = /href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/
            guard let match = attributes.firstMatch(of: hrefPattern.ignoresCase()) else { return nil }
            let raw = String(match.output.1 ?? match.output.2 ?? match.output.3 ?? "")
            let decoded = HTMLText.decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: decoded), let scheme = url.scheme?.lowercased(),
                  HTMLText.allowedSchemes.contains(scheme) else {
                return nil
            }
            return url
        }
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "amp": "&",
                     "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
                     "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "middot": "\u{00B7}"]
        let pattern = /&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/
        return text.replacing(pattern) { match in
            let body = String(match.output.1)
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? ""
            }
            if body.hasPrefix("#") {
                return UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) } ?? ""
            }
            return named[body.lowercased()] ?? String(match.output.0)
        }
    }
}
