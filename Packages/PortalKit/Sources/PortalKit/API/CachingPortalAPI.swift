import Foundation

/// Stores the last good response for each read endpoint.
public protocol ResponseCache: Sendable {
    func store(_ data: Data, for key: String) async
    func load(_ key: String) async -> (data: Data, savedAt: Date)?
    func clear() async
}

/// Files in Caches, encrypted at rest with complete file protection. Only response JSON is
/// stored; never file contents (spec §8).
public actor FileResponseCache: ResponseCache {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard() -> FileResponseCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return FileResponseCache(directory: caches.appending(path: "PortalCache", directoryHint: .isDirectory))
    }

    public func store(_ data: Data, for key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: key), options: [.atomic, .completeFileProtection])
        } catch {
            // A failed cache write only means less offline data.
        }
    }

    public func load(_ key: String) -> (data: Data, savedAt: Date)? {
        let url = url(for: key)
        guard let data = try? Data(contentsOf: url),
              let savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return nil
        }
        return (data, savedAt)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(for key: String) -> URL {
        // Keys are endpoint paths built from validated ids; make them safe file names anyway.
        let name = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return directory.appending(path: name + ".json")
    }
}

/// In-memory cache for tests and previews.
public actor MemoryResponseCache: ResponseCache {
    private var entries: [String: (Data, Date)] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func store(_ data: Data, for key: String) { entries[key] = (data, now()) }
    public func load(_ key: String) -> (data: Data, savedAt: Date)? { entries[key].map { ($0.0, $0.1) } }
    public func clear() { entries = [:] }
}

/// Wraps another `PortalAPI` with a read-only offline cache (spec §7, §8).
///
/// Online, reads go to the network and successful responses are saved. Offline (or when the
/// network call fails as offline), reads return the saved response and report its age; writes
/// throw `.offline` without trying.
public actor CachingPortalAPI: PortalAPI {
    private let base: PortalAPI
    private let cache: ResponseCache
    private var isOnline = true
    /// Called with the save time whenever cached data is shown.
    private let onServedFromCache: @Sendable (Date) async -> Void

    public init(base: PortalAPI, cache: ResponseCache, onServedFromCache: @escaping @Sendable (Date) async -> Void = { _ in }) {
        self.base = base
        self.cache = cache
        self.onServedFromCache = onServedFromCache
    }

    public func setOnline(_ online: Bool) {
        isOnline = online
    }

    public func clearCache() async {
        await cache.clear()
    }

    // MARK: Reads (cached)

    public func claims() async throws -> [ClaimSummary] { try await read("claims") { try await $0.claims() } }
    public func claim(id: String) async throws -> ClaimDetail { try await read("claims/\(id)") { try await $0.claim(id: id) } }
    public func claimPayments(id: String) async throws -> [Payment] { try await read("claims/\(id)/payments") { try await $0.claimPayments(id: id) } }
    public func leads() async throws -> [LeadSummary] { try await read("leads") { try await $0.leads() } }
    public func lead(id: String) async throws -> LeadDetail { try await read("leads/\(id)") { try await $0.lead(id: id) } }
    public func updates(for record: RecordRef) async throws -> [PortalUpdate] {
        try await read("\(record.collectionPath)/\(record.id)/updates") { try await $0.updates(for: record) }
    }
    public func files(for record: RecordRef) async throws -> [PortalFile] {
        try await read("\(record.collectionPath)/\(record.id)/files") { try await $0.files(for: record) }
    }
    public func activity() async throws -> [ActivityItem] { try await read("activity") { try await $0.activity() } }
    public func cases() async throws -> [SupportCase] { try await read("cases") { try await $0.cases() } }
    public func supportCase(id: String) async throws -> SupportCaseDetail { try await read("cases/\(id)") { try await $0.supportCase(id: id) } }

    // MARK: Online only (not cached, and they only matter while submitting)

    public func insuranceCompanies(matching query: String) async throws -> [InsuranceCompany] {
        try requireOnline()
        return try await base.insuranceCompanies(matching: query)
    }

    public func perilValues() async throws -> [String] { try await read("picklists/peril") { try await $0.perilValues() } }

    // MARK: Writes (refused offline)

    public func createLead(_ submission: LeadSubmission) async throws -> String {
        try requireOnline()
        return try await base.createLead(submission)
    }

    public func addComment(to record: RecordRef, text: String) async throws {
        try requireOnline()
        try await base.addComment(to: record, text: text)
    }

    public func markActivityRead(commentIds: [String]) async throws {
        try requireOnline()
        try await base.markActivityRead(commentIds: commentIds)
    }

    public func replyToCase(id: String, body: String) async throws {
        try requireOnline()
        try await base.replyToCase(id: id, body: body)
    }

    public func requestAssistance(recordId: String, comments: String) async throws -> String {
        try requireOnline()
        return try await base.requestAssistance(recordId: recordId, comments: comments)
    }

    // MARK: - Plumbing

    private func requireOnline() throws {
        guard isOnline else { throw PortalAPIError.offline }
    }

    private func read<T: Codable & Sendable>(_ key: String, _ fetch: @Sendable (PortalAPI) async throws -> T) async throws -> T {
        if isOnline {
            do {
                let value = try await fetch(base)
                if let data = try? PortalJSON.makeEncoder().encode(value) {
                    await cache.store(data, for: key)
                }
                return value
            } catch {
                // Only fall back for connectivity failures. A 404 must stay a 404.
                guard PortalAPIError.wrap(error) == .offline else { throw error }
            }
        }

        guard let cached = await cache.load(key),
              let value = try? PortalJSON.makeDecoder().decode(T.self, from: cached.data) else {
            throw PortalAPIError.offline
        }
        await onServedFromCache(cached.savedAt)
        return value
    }
}
