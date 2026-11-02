import Observation
import PortalKit
import SwiftUI

/// The claim or lead on screen, so Ask Alex starts with it as the conversation's context.
/// Record pages report themselves as they appear and disappear; switching tabs does both, and
/// opening the Ask Alex sheet does neither, so the last visible record is the one being viewed.
@MainActor
@Observable
final class AlexRecordContext {
    struct ViewedRecord: Equatable {
        let record: RecordRef
        var name: String?

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

    private var visible: [ViewedRecord] = []

    /// The record the user is looking at, if any.
    var current: ViewedRecord? { visible.last }

    func appeared(_ record: RecordRef, name: String?) {
        visible.removeAll { $0.record == record }
        visible.append(ViewedRecord(record: record, name: name))
    }

    func renamed(_ record: RecordRef, name: String?) {
        guard let index = visible.firstIndex(where: { $0.record == record }) else { return }
        visible[index].name = name
    }

    func disappeared(_ record: RecordRef) {
        visible.removeAll { $0.record == record }
    }
}

extension EnvironmentValues {
    /// Set by the main tabs for staff; nil elsewhere (and record pages then report nothing).
    @Entry var alexRecordContext: AlexRecordContext? = nil
}

extension View {
    /// Tells Ask Alex this claim or lead is on screen.
    func reportsViewedRecord(_ record: RecordRef, name: String?) -> some View {
        modifier(ReportsViewedRecord(record: record, name: name))
    }
}

private struct ReportsViewedRecord: ViewModifier {
    let record: RecordRef
    let name: String?
    @Environment(\.alexRecordContext) private var context

    func body(content: Content) -> some View {
        content
            .onAppear { context?.appeared(record, name: name) }
            .onDisappear { context?.disappeared(record) }
            .onChange(of: name) { _, name in context?.renamed(record, name: name) }
    }
}
