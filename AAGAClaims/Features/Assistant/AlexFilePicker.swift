import SwiftUI

/// Files Alex asked the user to choose from, shown as checkboxes; the picked names go back
/// as the user's reply. Alex lists them grouped under a line naming the kind ("Carrier
/// estimates:"), either as a checklist ("- [ ] File name") or as plain bullets followed by a
/// question asking which file, estimate, report or document to use.
nonisolated struct AlexFileChoice: Identifiable, Equatable, Sendable {
    struct Section: Equatable {
        var title: String?
        var files: [String]
    }

    let id = UUID()
    var sections: [Section]

    var allFiles: [String] { sections.flatMap(\.files) }

    /// The files to choose from in one of Alex's replies, or nil when it isn't asking for a choice.
    static func parse(_ text: String) -> AlexFileChoice? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if let checklist = sections(in: lines, item: checklistItem) { return checklist }
        // Plain bullets only count when the reply ends by asking which file to use.
        guard let question = lines.last(where: { !$0.isEmpty }), asksForFiles(question) else { return nil }
        return sections(in: lines, item: fileBullet)
    }

    private static func sections(in lines: [String], item: (String) -> String?) -> AlexFileChoice? {
        var sections: [Section] = []
        var heading: String?
        var current: Section?
        for line in lines {
            if let file = item(line) {
                if current == nil { current = Section(title: heading, files: []) }
                if !(current?.files.contains(file) ?? true) { current?.files.append(file) }
            } else if !line.isEmpty {
                if let done = current { sections.append(done) }
                current = nil
                heading = title(line)
            }
        }
        if let done = current { sections.append(done) }
        return sections.isEmpty ? nil : AlexFileChoice(sections: sections)
    }

    /// "Which carrier estimate should I use?", "Pick the report to compare." and the like.
    private static func asksForFiles(_ line: String) -> Bool {
        let l = line.lowercased()
        let asks = ["which", "choose", "pick", "select"].contains { l.contains($0) }
        let files = ["estimate", "report", "file", "document", "pdf", "eagleview", "hover", "roofr",
                     "policy", "letter", "scope", "measurement", "photo"].contains { l.contains($0) }
        return asks && files
    }

    /// "- [ ] Name", "* [ ] [Name](link)" or "• [ ] **Name**" → "Name".
    private static func checklistItem(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^[-*•]\s*\[\s?\]\s+(.+)$/#) else { return nil }
        return cleanName(String(match.1))
    }

    /// "- Name" when the bullet is just a file name: not "RCV: $19,661.01" or "Smith | Negotiations".
    private static func fileBullet(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^[-*•]\s+(.+)$/#), let name = cleanName(String(match.1)) else { return nil }
        let notAFile = name.contains("|") || name.contains("$") || name.contains(": ") || name.hasSuffix("?")
            || name.split(separator: " ").count > 14
        return notAFile ? nil : name
    }

    /// Strips a Markdown link and bold: "[Name](url)" or "**Name**" → "Name".
    private static func cleanName(_ text: String) -> String? {
        var name = text
        if let link = name.firstMatch(of: #/^\[(.+?)\]\([^)]*\)(.*)$/#) {
            name = String(link.1) + String(link.2)
        }
        name = name.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// "**Carrier estimates on this claim:**" → "Carrier estimates on this claim".
    private static func title(_ line: String) -> String {
        var title = line.replacingOccurrences(of: "**", with: "")
        while title.hasPrefix("#") { title.removeFirst() }
        title = title.trimmingCharacters(in: .whitespaces)
        if title.hasSuffix(":") { title.removeLast() }
        return title
    }

    /// What the user "says" when they confirm their picks.
    static func reply(for files: [String]) -> String {
        files.count == 1 ? "Use this file: \(files[0])" : "Use these files: " + files.joined(separator: "; ")
    }
}

/// Checkboxes for the files Alex listed, over the chat.
struct AlexFilePickerSheet: View {
    let choice: AlexFileChoice
    let send: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(choice.sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.files, id: \.self) { file in
                            Button {
                                if picked.contains(file) { picked.remove(file) } else { picked.insert(file) }
                            } label: {
                                Label {
                                    Text(file)
                                        .foregroundStyle(Color.primary)
                                        .multilineTextAlignment(.leading)
                                } icon: {
                                    Image(systemName: picked.contains(file) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(picked.contains(file) ? Color.accentColor : Color.secondary)
                                        .imageScale(.large)
                                }
                            }
                            .accessibilityAddTraits(picked.contains(file) ? .isSelected : [])
                        }
                    } header: {
                        if let title = section.title, !title.isEmpty { Text(title) }
                    }
                }
            }
            .navigationTitle("Choose files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Type instead") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    // Keep Alex's order, not the order they were tapped.
                    send(AlexFileChoice.reply(for: choice.allFiles.filter(picked.contains)))
                    dismiss()
                } label: {
                    Text(picked.isEmpty ? "Select files" : "Use \(picked.count) file\(picked.count == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(picked.isEmpty)
                .padding()
                .background(.bar)
            }
        }
    }
}
