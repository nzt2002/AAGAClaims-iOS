#if DEBUG
import PortalKit
import SwiftUI

/// View models backed by the bundled fixtures, for SwiftUI previews.
enum PreviewData {
    static func api() -> MockPortalAPI {
        MockPortalAPI.standard(latency: .zero)
    }

    static func router() -> AppRouter {
        let router = AppRouter(api: api())
        Task { await router.home.load() }
        return router
    }

    static func loadedHome() -> HomeViewModel {
        let viewModel = HomeViewModel(api: api())
        Task { await viewModel.load() }
        return viewModel
    }

    static func loadedClaims() -> ClaimsListViewModel {
        let viewModel = ClaimsListViewModel(api: api())
        Task { await viewModel.load() }
        return viewModel
    }

    static func loadedLeads() -> LeadsListViewModel {
        let viewModel = LeadsListViewModel(api: api())
        Task { await viewModel.load() }
        return viewModel
    }

    static func loadedCases() -> CasesListViewModel {
        let viewModel = CasesListViewModel(api: api())
        Task { await viewModel.load() }
        return viewModel
    }
}
#endif
