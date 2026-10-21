import Foundation
import MetricKit
import PortalKit

/// Crash and hang reports (MetricKit), sent to Salesforce's Mobile App Logs so problems are seen
/// without waiting for someone to report them. iOS delivers a report on the next launch after the
/// problem; it waits on the device until it's sent. Call stacks only: no customer data.
/// Not main-actor: MetricKit calls `didReceive` on a background queue, and the main-actor
/// isolation check crashed the app at launch whenever a report was waiting (1.1.0 build 26).
nonisolated final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReporter()

    private let lock = NSLock()
    private let fileURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "PendingDiagnostics.json")

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var items: [DiagnosticsReport.Item] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let reason = [crash.exceptionType.map { "Exception \($0)" }, crash.signal.map { "Signal \($0)" }, crash.terminationReason]
                    .compactMap { $0 }.joined(separator: " · ")
                items.append(.init(kind: "App crash", reason: String((reason.isEmpty ? "Crash" : reason).prefix(255)),
                                   details: Self.text(crash.callStackTree.jsonRepresentation(), meta: crash.metaData)))
            }
            for hang in payload.hangDiagnostics ?? [] {
                items.append(.init(kind: "App hang", reason: "Unresponsive for \(hang.hangDuration.formatted())",
                                   details: Self.text(hang.callStackTree.jsonRepresentation(), meta: hang.metaData)))
            }
        }
        guard !items.isEmpty else { return }
        lock.withLock { save(load() + items) }
    }

    /// Sends waiting reports, five at a time. Kept for next time if sending fails.
    func send(using api: PortalAPI) async {
        let pending = lock.withLock { load() }
        guard !pending.isEmpty else { return }
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        var device = utsname()
        uname(&device)
        let model = withUnsafeBytes(of: device.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let deviceName = "\(model) iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        var sent = 0
        for batch in stride(from: 0, to: pending.count, by: 5).map({ Array(pending[$0..<min($0 + 5, pending.count)]) }) {
            do {
                try await api.sendDiagnostics(DiagnosticsReport(appVersion: version, device: String(deviceName.prefix(100)), reports: batch))
                sent += batch.count
            } catch {
                break
            }
        }
        if sent > 0 {
            lock.withLock { save(Array(load().dropFirst(sent))) }
        }
    }

    private static func text(_ json: Data, meta: MXMetaData) -> String {
        let stack = String(decoding: json, as: UTF8.self)
        let context = "App \(meta.applicationBuildVersion), \(meta.osVersion), \(meta.deviceType)\n"
        return String((context + stack).prefix(30_000))
    }

    private func load() -> [DiagnosticsReport.Item] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticsReport.Item].self, from: data)) ?? []
    }

    private func save(_ items: [DiagnosticsReport.Item]) {
        // At most 20 waiting; the newest matter most.
        let kept = Array(items.suffix(20))
        if kept.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else if let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
