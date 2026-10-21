import SwiftUI

extension EnvironmentValues {
    /// Shared by list rows and record pages for the zoom transition. Nil turns it off (iPad split view).
    @Entry var recordZoomNamespace: Namespace.ID? = nil
}

extension View {
    /// Marks a row as the place a record zooms out of.
    func recordZoomSource(_ id: String) -> some View {
        modifier(RecordZoomSource(id: id))
    }

    /// A record page that zooms out of its row (iPhone; a plain push elsewhere or with Reduce Motion).
    func recordZoomDestination(_ id: String) -> some View {
        modifier(RecordZoomDestination(id: id))
    }
}

private struct RecordZoomSource: ViewModifier {
    let id: String
    @Environment(\.recordZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct RecordZoomDestination: ViewModifier {
    let id: String
    @Environment(\.recordZoomNamespace) private var namespace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let namespace, sizeClass == .compact, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
