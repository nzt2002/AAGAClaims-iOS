import PDFKit
import PortalKit
import SwiftUI

/// Staff e-sign (in-house pilot): pick an active Word template, merge the claim or lead into it on
/// the server, preview it, and send it for signature. Opened from the E-Sign action. `isAvailable`
/// becomes true only when the server returns templates, so users outside the pilot (403) keep the
/// old Docs Made Easy E-Sign until switchover.
struct DocumentGeneration: ViewModifier {
    let record: RecordRef
    let recordName: String
    let api: PortalAPI
    @Binding var isPresented: Bool
    @Binding var isAvailable: Bool

    @Environment(\.isInternalUser) private var isInternal
    @State private var templates: [DocumentTemplate] = []

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                GenerateDocumentSheet(record: record, recordName: recordName, templates: templates, api: api)
            }
            .task(id: record) {
                guard isInternal else { return }
                // 403 (not in the pilot) or offline: not available.
                templates = (try? await api.documentTemplates(for: record)) ?? []
                isAvailable = !templates.isEmpty
            }
    }
}

extension View {
    func documentGeneration(record: RecordRef, recordName: String, api: PortalAPI,
                            isPresented: Binding<Bool>, isAvailable: Binding<Bool>) -> some View {
        modifier(DocumentGeneration(record: record, recordName: recordName, api: api,
                                    isPresented: isPresented, isAvailable: isAvailable))
    }
}

struct GenerateDocumentSheet: View {
    let record: RecordRef
    let recordName: String
    let templates: [DocumentTemplate]
    let api: PortalAPI

    @Environment(\.dismiss) private var dismiss
    @State private var generating: DocumentTemplate?
    @State private var document: GeneratedDocument?
    @State private var pdfURL: URL?
    @State private var saving = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var selectedTemplate: DocumentTemplate?
    @State private var showingSend = false
    @State private var requests: [SignatureRequestSummary] = []
    @State private var sentMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let document, let pdfURL {
                    documentView(document, url: pdfURL)
                } else {
                    templateList
                        .navigationTitle("E-Sign")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Couldn't generate the document", isPresented: showingError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
            .alert("Sent for signature", isPresented: showingSent, presenting: sentMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
        }
        .task { await loadRequests() }
        .onDisappear(perform: cleanUp)
    }

    private func documentView(_ document: GeneratedDocument, url: URL) -> some View {
        PDFKitView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { documentToolbar }
            .navigationDestination(isPresented: $showingSend) { sendDestination }
    }

    @ViewBuilder
    private var sendDestination: some View {
        if let selectedTemplate {
            SendForSignatureView(record: record, template: selectedTemplate, api: api, onSent: sentForSignature)
        }
    }

    private func sentForSignature() {
        showingSend = false
        document = nil
        cleanUp()
        pdfURL = nil
        sentMessage = "Each signer has been emailed a personal signing link. You'll get the signed copy by email when everyone has signed."
        Task { await loadRequests() }
    }

    private var templateList: some View {
        List {
            Section {
                ForEach(templates) { template in
                    Button {
                        Task { await generate(template) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(template.name).foregroundStyle(.primary)
                                Text(subtitle(template)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if generating == template {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(minHeight: Theme.minTapTarget)
                    }
                    .disabled(generating != nil)
                    .accessibilityIdentifier("template-\(template.id)")
                }
            } header: {
                Text("Templates for \(recordName)")
            } footer: {
                Text("The record's current details are merged into the template. Nothing is saved until you choose Save to Files or Send for Signature.")
            }
            if !requests.isEmpty {
                Section("E-sign requests") {
                    ForEach(requests) { request in
                        SignatureRequestRow(request: request)
                    }
                }
            }
        }
        .refreshable { await loadRequests() }
    }

    @ToolbarContentBuilder
    private var documentToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if let pdfURL {
                ShareLink(item: pdfURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Spacer()
            if (selectedTemplate?.signerCount ?? 0) > 0 {
                Button {
                    showingSend = true
                } label: {
                    Label("Send for Signature", systemImage: "signature")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("sendForSignature")
                Spacer()
            }
            Button {
                Task { await save() }
            } label: {
                if saving {
                    ProgressView()
                } else {
                    Label(saved ? "Saved" : "Save to Files", systemImage: saved ? "checkmark.circle.fill" : "tray.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
            }
            .disabled(saving || saved)
            .accessibilityIdentifier("saveDocument")
        }
    }

    private func subtitle(_ template: DocumentTemplate) -> String {
        switch template.signerCount {
        case 0: "No signatures"
        case 1: "1 signer"
        default: "\(template.signerCount) signers"
        }
    }

    private var showingSent: Binding<Bool> {
        Binding(get: { sentMessage != nil }, set: { if !$0 { sentMessage = nil } })
    }

    private func loadRequests() async {
        if let rows = try? await api.signatureRequests(for: record) {
            requests = rows
        }
    }

    private var showingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func generate(_ template: DocumentTemplate) async {
        generating = template
        defer { generating = nil }
        do {
            let result = try await api.generateDocument(templateId: template.id, for: record, save: false)
            guard let data = result.pdfData else { throw PortalAPIError.decoding("PDF") }
            pdfURL = try write(data, title: result.title)
            saved = false
            document = result
            selectedTemplate = template
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Generates again with `save` so the server files the exact PDF on the record.
    private func save() async {
        guard let template = selectedTemplate else { return }
        saving = true
        defer { saving = false }
        do {
            let result = try await api.generateDocument(templateId: template.id, for: record, save: true)
            saved = result.contentDocumentId != nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func write(_ data: Data, title: String) throws -> URL {
        cleanUp()
        let safe = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safe).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// The PDF can hold personal data: don't leave it in tmp.
    private func cleanUp() {
        if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
    }

    private func message(for error: Error) -> String {
        switch error as? PortalAPIError {
        case .rejected(let text): text
        case .offline: "You're offline."
        default: "Please try again."
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
