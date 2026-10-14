import Foundation
import Observation

/// A person from search (staff only): their profile and their Chatter profile feed.
@MainActor
@Observable
public final class PersonViewModel {
    public let personId: String
    public private(set) var person: LoadState<Person> = .idle
    public let chatter: ChatterFeedViewModel

    private let api: PortalAPI

    public init(api: PortalAPI, personId: String) {
        self.api = api
        self.personId = personId
        self.chatter = ChatterFeedViewModel(api: api, source: .person(personId))
    }

    public func load() async {
        async let person: Void = loadPerson()
        async let feed: Void = chatter.load()
        _ = await (person, feed)
    }

    private func loadPerson() async {
        let api = self.api, id = personId
        await PortalKit.load(self, \.person) { try await api.person(id: id) }
    }
}
