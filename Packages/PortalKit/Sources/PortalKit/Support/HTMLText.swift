import Foundation

/// Plain-text previews of update bodies, which are HTML (spec §3).
/// Full rich rendering (links, bold) comes with the Update sheet in milestone 5.
public enum HTMLText {
    /// Drops scripts, styles and tags, decodes common entities and collapses whitespace.
    public static func plainText(_ html: String?) -> String {
        guard var text = html, !text.isEmpty else { return "" }

        for tag in ["script", "style"] {
            text = text.replacingOccurrences(
                of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(
            of: "<\\s*(br|/p|/div|/li)\\b[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&amp;": "&"]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
