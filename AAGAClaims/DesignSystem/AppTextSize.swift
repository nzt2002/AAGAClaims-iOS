import SwiftUI

/// The Text size setting in Account → Appearance: Default follows the iPhone's setting; Large and Extra large
/// make everything one or two steps bigger than it, as on the ProClaimer website.
enum AppTextSize: String, CaseIterable, Identifiable {
    case standard, large, larger

    static let storageKey = "textSize"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Extra large"
        }
    }

    /// How many Dynamic Type steps bigger than the iPhone's setting.
    var steps: Int {
        switch self {
        case .standard: 0
        case .large: 1
        case .larger: 2
        }
    }
}

extension DynamicTypeSize {
    /// This size, `steps` bigger (stopping at the largest accessibility size).
    func stepped(by steps: Int) -> DynamicTypeSize {
        guard steps > 0 else { return self }
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        return all[min(index + steps, all.count - 1)]
    }
}

/// Applies the person's text size under the iPhone's own. Put it at the top of the app, where the
/// environment still holds the iPhone's setting.
struct AppTextSizeRoot<Content: View>: View {
    @AppStorage(AppTextSize.storageKey) private var size = AppTextSize.standard
    @Environment(\.dynamicTypeSize) private var system
    @ViewBuilder let content: Content

    var body: some View {
        content.dynamicTypeSize(system.stepped(by: size.steps))
    }
}
