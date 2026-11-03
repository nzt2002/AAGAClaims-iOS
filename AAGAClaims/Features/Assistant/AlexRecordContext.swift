import Observation
import PortalKit
import SwiftUI

/// The claim or lead the user is working in, so Ask Alex starts with it as the conversation's
/// context. Record pages report themselves as they appear and disappear. A page stays the context
/// while something is pushed on top of it (an activity, a case, a file) and while another tab is
/// shown; it's dropped only when it's closed (popped). Each record remembers its tab, so the
/// context is the newest record open in the tab on screen.
@MainActor
@Observable
final class AlexRecordContext {
    struct ViewedRecord: Equatable {
        let record: RecordRef
        var name: String?
        /// Something an adjuster recognizes and Alex can search on: the carrier claim number, or
        /// the loss address. Never a Salesforce Id (users see the opening line).
        var hint: String?
        var tab: AppTab?

        var objectApiName: String {
            switch record {
            case .claim: "Claims2__c"
            case .lead: "Prospects__c"
            }
        }

        var noun: String {
            switch record {
            case .claim: "claim"
            case .lead: "lead"
            }
        }
    }

    private var open: [ViewedRecord] = []

    /// The newest record still open in `tab`.
    func current(in tab: AppTab) -> ViewedRecord? {
        open.last { $0.tab == nil || $0.tab == tab }
    }

    func appeared(_ record: RecordRef, name: String?, hint: String?, tab: AppTab?) {
        open.removeAll { $0.record == record && $0.tab == tab }
        open.append(ViewedRecord(record: record, name: name, hint: hint, tab: tab))
    }

    func updated(_ record: RecordRef, name: String?, hint: String?, tab: AppTab?) {
        guard let index = open.lastIndex(where: { $0.record == record && $0.tab == tab }) else { return }
        open[index].name = name
        open[index].hint = hint
    }

    /// `stillPresented`: the page is covered (a child pushed, another tab shown), not closed.
    func disappeared(_ record: RecordRef, tab: AppTab?, stillPresented: Bool) {
        guard !stillPresented else { return }
        open.removeAll { $0.record == record && $0.tab == tab }
    }
}

extension EnvironmentValues {
    /// Set by the main tabs for staff; nil elsewhere (and record pages then report nothing).
    @Entry var alexRecordContext: AlexRecordContext? = nil
    /// The tab a view lives in, so Alex's context follows the tab on screen.
    @Entry var alexTab: AppTab? = nil
}

extension View {
    /// Tells Ask Alex this claim or lead is open.
    func reportsViewedRecord(_ record: RecordRef, name: String?, hint: String?) -> some View {
        modifier(ReportsViewedRecord(record: record, name: name, hint: hint))
    }
}

private struct ReportsViewedRecord: ViewModifier {
    let record: RecordRef
    let name: String?
    let hint: String?
    @Environment(\.alexRecordContext) private var context
    @Environment(\.alexTab) private var tab
    @Environment(\.isPresented) private var isPresented

    func body(content: Content) -> some View {
        content
            .onAppear { context?.appeared(record, name: name, hint: hint, tab: tab) }
            .onDisappear { context?.disappeared(record, tab: tab, stillPresented: isPresented) }
            .onChange(of: name) { _, name in context?.updated(record, name: name, hint: hint, tab: tab) }
            .onChange(of: hint) { _, hint in context?.updated(record, name: name, hint: hint, tab: tab) }
    }
}
