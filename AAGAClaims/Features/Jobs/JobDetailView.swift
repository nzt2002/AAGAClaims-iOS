import PortalKit
import SwiftUI

/// One job, like the website's job page: where it is on its board (tap to move it), the customer and site, what's scheduled,
/// its estimates and invoices, and the updates and files shared. For the Contractor add-on, in place of a claim.
struct JobDetailView: View {
    @State private var viewModel: JobDetailViewModel
    let api: PortalAPI
    let fallbackName: String?
    @Environment(\.isInternalUser) private var isInternal
    @State private var section: Section = .overview
    @State private var choosingStage = false

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", work = "Work", money = "Money", updates = "Updates", files = "Files"
        var id: String { rawValue }
    }

    init(jobId: String, fallbackName: String?, api: PortalAPI) {
        _viewModel = State(initialValue: JobDetailViewModel(jobId: jobId, api: api))
        self.api = api
        self.fallbackName = fallbackName
    }

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "this job", retry: { Task { await viewModel.load() } }) { job in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header(job)
                    stageTrack(job)
                    Picker("Section", selection: $section) {
                        ForEach(visibleSections(job)) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch section {
                    case .overview: overview(job)
                    case .work: work(job)
                    case .money: money(job)
                    case .updates: updates
                    case .files: files
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle(viewModel.state.value?.name ?? fallbackName ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.state.value == nil { await viewModel.load() } }
        .onChange(of: section) { _, now in
            Task {
                if now == .updates, viewModel.updates.value == nil { await viewModel.loadUpdates() }
                if now == .files, viewModel.files.value == nil { await viewModel.loadFiles() }
            }
        }
        .confirmationDialog("Move to stage", isPresented: $choosingStage, titleVisibility: .visible) {
            ForEach(viewModel.state.value?.stages ?? [], id: \.name) { stage in
                Button(stage.name) { Task { await viewModel.move(to: stage.name) } }
            }
        }
        .alert("Couldn't move the job", isPresented: Binding(get: { viewModel.moveError != nil }, set: { _ in })) {
            Button("OK", role: .cancel) {}
        } message: { Text("You may not have permission to move it. Try again.") }
    }

    private func visibleSections(_ job: JobDetail) -> [Section] {
        Section.allCases.filter { $0 != .money || (job.canSeeMoney ?? false) }
    }

    // MARK: Header and stage

    private func header(_ job: JobDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name).font(.title3.weight(.semibold)).foregroundStyle(Color.textPrimary)
                    if let number = PortalFormat.nonEmpty(job.number) { Text(number).font(.caption).foregroundStyle(Color.textSecondary) }
                }
                Spacer()
                StatusPill(text: job.isComplete ? "Complete" : job.stage, tone: job.isComplete ? .success : .active)
            }
            InfoRow(label: "Job site", value: job.address, systemImage: "mappin.and.ellipse")
            InfoRow(label: "Trade", value: job.trade, systemImage: "hammer")
            if let start = job.startDate, !job.isComplete { InfoRow(label: "Starts", value: PortalFormat.date(start), systemImage: "calendar") }
            if let amount = job.contractAmount, job.canSeeMoney ?? false { InfoRow(label: "Contract", value: PortalFormat.currency(amount), systemImage: "dollarsign.circle") }
        }
        .cardStyle()
    }

    private func stageTrack(_ job: JobDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Stage \(job.stageNumber) of \(job.stageTotal)").font(.subheadline.weight(.semibold))
                Spacer()
                if isInternal, !job.stages.isEmpty {
                    Button { choosingStage = true } label: {
                        Label(viewModel.isMoving ? "Moving…" : "Move", systemImage: "arrow.right.circle").iconShadow()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isMoving)
                    .accessibilityIdentifier("moveJobStage")
                }
            }
            ProgressView(value: Double(job.stageNumber), total: Double(max(job.stageTotal, 1))).tint(.brandTheme)
            // Every stage, the finished ones ticked and the current one highlighted
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(job.stages.enumerated()), id: \.offset) { index, stage in
                    let done = job.isComplete || index < job.stageNumber - 1
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: stage.current ? "circle.inset.filled" : (done ? "checkmark.circle.fill" : "circle")).iconShadow()
                            .foregroundStyle(stage.current ? Color.brandTheme : (done ? Color.success : Color.textSecondary))
                        Text(stage.name).font(stage.current ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(stage.current ? Color.textPrimary : Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle()
    }

    // MARK: Sections

    @ViewBuilder
    private func overview(_ job: JobDetail) -> some View {
        if let customer = job.customer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Customer")
                InfoRow(label: "Name", value: customer.name, systemImage: "person")
                if let phone = PortalFormat.nonEmpty(customer.phone), let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) { Label(phone, systemImage: "phone").iconShadow() }.accessibilityIdentifier("callCustomer")
                }
                if let email = PortalFormat.nonEmpty(customer.email), let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) { Label(email, systemImage: "envelope").iconShadow() }
                }
            }
            .cardStyle()
        }
        if let tasks = job.openTasks, tasks > 0 {
            Label("\(tasks) open task\(tasks == 1 ? "" : "s")", systemImage: "checklist").iconShadow().cardStyle()
        }
        if job.canSeeMoney ?? false, job.balanceDue > 0 {
            Label("\(PortalFormat.currency(job.balanceDue)) still owed", systemImage: "dollarsign.circle").iconShadow().cardStyle()
        }
        if job.estimates.isEmpty && job.invoices.isEmpty && job.work.isEmpty && job.customer == nil {
            Text("Nothing here yet.").foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private func work(_ job: JobDetail) -> some View {
        if job.work.isEmpty {
            ContentUnavailableView("No work scheduled", systemImage: "calendar", description: Text("Work orders for this job will show here."))
        } else {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(job.work) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(w.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            StatusPill(text: w.status, tone: w.status == "Complete" ? .success : (w.status == "In progress" ? .active : .neutral))
                        }
                        let when = [w.startDate.map { PortalFormat.date($0) }, w.endDate.flatMap { $0 == w.startDate ? nil : "to \(PortalFormat.date($0))" }].compactMap { $0 }.joined(separator: " ")
                        Text([when.isEmpty ? "Date to come" : when, w.arrival.map { "arrives about \($0)" }, w.crew].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    .cardStyle()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func money(_ job: JobDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Estimates")
            if job.estimates.isEmpty { Text("No estimates yet.").foregroundStyle(Color.textSecondary) }
            ForEach(job.estimates) { e in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.subheadline.weight(.semibold))
                        Text([e.number, e.validUntil.map { "good until \(PortalFormat.date($0))" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let total = e.total { Text(PortalFormat.currency(total)).font(.subheadline.weight(.semibold)) }
                        StatusPill(text: e.status, tone: e.status == "Accepted" ? .success : (e.status == "Sent" ? .active : (e.status == "Declined" ? .warning : .neutral)))
                    }
                }
                .cardStyle().accessibilityElement(children: .combine)
            }
            SectionHeader("Invoices")
            if job.invoices.isEmpty { Text("No invoices yet.").foregroundStyle(Color.textSecondary) }
            ForEach(job.invoices) { i in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(i.type ?? "Invoice") invoice").font(.subheadline.weight(.semibold))
                        Text([i.number, i.dueDate.map { "due \(PortalFormat.date($0))" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PortalFormat.currency(i.total)).font(.subheadline.weight(.semibold))
                        if let balance = i.balance, balance > 0, i.status != "Draft" { Text("\(PortalFormat.currency(balance)) due").font(.caption).foregroundStyle(Color.warning) }
                        StatusPill(text: i.status, tone: i.status == "Paid" ? .success : (i.status == "Partially Paid" ? .warning : (i.status == "Sent" ? .active : .neutral)))
                    }
                }
                .cardStyle().accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var updates: some View {
        switch viewModel.updates {
        case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding()
        case .failed: Text("Couldn't load updates.").foregroundStyle(Color.textSecondary)
        case .loaded(let items, _):
            if items.isEmpty {
                ContentUnavailableView("No updates yet", systemImage: "megaphone", description: Text("Updates the team shares will show here."))
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(items) { u in
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = PortalFormat.nonEmpty(u.title) { Text(title).font(.subheadline.weight(.semibold)) }
                            Text(HTMLText.plainText(u.text)).font(.subheadline).foregroundStyle(Color.textPrimary)
                            Text(PortalFormat.date(u.createdDate)).font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        .cardStyle()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var files: some View {
        switch viewModel.files {
        case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding()
        case .failed: Text("Couldn't load files.").foregroundStyle(Color.textSecondary)
        case .loaded(let items, _):
            if items.isEmpty {
                ContentUnavailableView("No files yet", systemImage: "folder", description: Text("Photos and documents for this job will show here."))
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(items) { f in
                        HStack {
                            Image(systemName: "doc").iconShadow().foregroundStyle(Color.brandTheme)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title ?? "File").font(.subheadline.weight(.semibold))
                                Text([f.fileType, PortalFormat.fileSize(f.contentSize), PortalFormat.date(f.createdDate)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                        }
                        .cardStyle()
                    }
                }
            }
        }
    }
}
