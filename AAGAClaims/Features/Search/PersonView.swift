import PortalKit
import SwiftUI

/// Pushes a person's page inside the search sheet.
struct PersonRoute: Hashable {
    let id: String
    let name: String?
}

/// A colleague from search (staff only): their profile and Chatter feed. Replies are written and
/// edited right here.
struct PersonView: View {
    @State private var viewModel: PersonViewModel
    let name: String?

    init(api: PortalAPI, personId: String, name: String?) {
        _viewModel = State(initialValue: PersonViewModel(api: api, personId: personId))
        self.name = name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                profile
                SectionHeader("Chatter")
                ChatterFeedSection(model: viewModel.chatter, emptyMessage: "No Chatter posts yet.")
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground)
        .navigationTitle(name ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task {
            if viewModel.person.value == nil { await viewModel.load() }
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profile: some View {
        switch viewModel.person {
        case .idle, .loading:
            SkeletonList(rows: 1)
        case .failed:
            ErrorStateView(subject: "this profile") { Task { await viewModel.load() } }
        case .loaded(let person, _):
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    Text(person.initials)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(BrandGradient.hero(.light), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name ?? "")
                            .font(.title3.bold())
                            .foregroundStyle(Color.textPrimary)
                        if let role = PortalFormat.nonEmpty([person.title, person.department].compactMap { $0 }.joined(separator: " · ")) {
                            Text(role)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        if let place = PortalFormat.nonEmpty([person.city, person.state].compactMap { $0 }.joined(separator: ", ")) {
                            Label(place, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("personHeader")

                if person.email != nil || person.phone != nil || person.mobilePhone != nil {
                    Divider()
                    contact("envelope", person.email, url: person.email.map { "mailto:\($0)" })
                    contact("phone", person.phone, url: person.phone.map(telURL))
                    contact("iphone", person.mobilePhone, url: person.mobilePhone.map(telURL))
                }
                if let manager = PortalFormat.nonEmpty(person.managerName) {
                    Label("Reports to \(manager)", systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                if let about = PortalFormat.nonEmpty(person.aboutMe) {
                    Text(about)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private func contact(_ icon: String, _ value: String?, url: String?) -> some View {
        if let value = PortalFormat.nonEmpty(value), let url = url.flatMap(URL.init(string:)) {
            Link(destination: url) {
                Label(value, systemImage: icon)
                    .font(.subheadline)
                    .frame(minHeight: Theme.minTapTarget, alignment: .leading)
            }
        }
    }

    private func telURL(_ number: String) -> String {
        "tel:" + number.filter { $0.isNumber || $0 == "+" }
    }

}
