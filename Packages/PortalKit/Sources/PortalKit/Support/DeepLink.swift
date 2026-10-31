import Foundation

/// Where a deep link, universal link or push notification should take the user (spec §8).
public enum DeepLink: Hashable, Sendable {
    case claim(id: String)
    case lead(id: String)
    case supportCase(id: String)
    /// A published update: open the record. `commentId` identifies the update.
    case update(record: RecordRef, commentId: String?)

    public static let scheme = "aagaclaims"
    public static let portalHost = "portal.accurateadjustmentsga.com"
    /// Universal links: Salesforce serves its own apple-app-site-association on the portal domain,
    /// so the app's links use this domain instead (Tools/universal-links). Same paths as the portal,
    /// which it redirects to when the app isn't installed.
    public static let appLinkHost = "app.accurateadjustmentsga.com"

    /// Key prefixes of the record ids the app can open, from the org's EntityDefinition.
    public enum KeyPrefix {
        public static let claim = "a23"   // Claims2__c
        public static let lead = "a0r"    // Prospects__c
        public static let supportCase = "500"
    }

    /// Parses:
    /// - `aagaclaims://claim/{id}`, `aagaclaims://lead/{id}`, `aagaclaims://case/{id}`
    /// - `https://portal.accurateadjustmentsga.com/s/detail/{id}` (claim or lead, by key prefix)
    /// - `https://portal.accurateadjustmentsga.com/s/my-case-detail?recordId={id}`
    /// - the same paths on `app.accurateadjustmentsga.com` (universal links)
    public init?(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if url.scheme?.lowercased() == Self.scheme {
            // aagaclaims://claim/{id}: "claim" is the host, the id is the first path component.
            let kind = url.host()?.lowercased()
            // Exactly one path component: the id.
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 1, let id = parts.first, Self.isValidId(id) else { return nil }
            switch kind {
            case "claim": self = .claim(id: id)
            case "lead": self = .lead(id: id)
            case "case": self = .supportCase(id: id)
            default: return nil
            }
            return
        }

        guard url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), host == Self.portalHost || host == Self.appLinkHost else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }

        // /s/my-case-detail?recordId={id}
        if path.count >= 2, path[0] == "s", path[1] == "my-case-detail" {
            guard let id = components?.queryItems?.first(where: { $0.name == "recordId" })?.value,
                  Self.isValidId(id), id.hasPrefix(KeyPrefix.supportCase) else { return nil }
            self = .supportCase(id: id)
            return
        }

        // /s/detail/{id}
        // The portal adds an object name after the id (/s/detail/{id}/{name}); ignore it.
        if path.count >= 3, path[0] == "s", path[1] == "detail" {
            guard let link = Self.record(forId: path[2]) else { return nil }
            self = link
            return
        }

        return nil
    }

    /// A push payload: `{ "type": "update" | "caseReply" | "case" | "payment" | "mention" | "post" | "task" | "esign",
    /// "recordId": "...", "commentId": "..." }`. "case" (a case update) carries the case id for homeowners
    /// and the case's claim or lead for staff, who don't open cases in the app.
    public init?(pushPayload userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String,
              let recordId = userInfo["recordId"] as? String, Self.isValidId(recordId) else { return nil }
        let commentId = userInfo["commentId"] as? String

        switch type {
        case "update":
            if recordId.hasPrefix(KeyPrefix.claim) {
                self = .update(record: .claim(recordId), commentId: commentId)
            } else if recordId.hasPrefix(KeyPrefix.lead) {
                self = .update(record: .lead(recordId), commentId: commentId)
            } else {
                return nil
            }
        case "caseReply":
            guard recordId.hasPrefix(KeyPrefix.supportCase) else { return nil }
            self = .supportCase(id: recordId)
        case "case" where recordId.hasPrefix(KeyPrefix.supportCase):
            self = .supportCase(id: recordId)
        case "payment", "mention", "task", "post", "esign", "case":
            // A payment, an @mention, a Chatter post, a task, an e-sign status change or (for staff)
            // a case update on a claim or lead: open the record.
            guard let record = Self.record(forId: recordId) else { return nil }
            self = record
        default:
            return nil
        }
    }

    /// A claim or lead by key prefix; nil for anything else.
    public static func record(forId id: String) -> DeepLink? {
        guard isValidId(id) else { return nil }
        if id.hasPrefix(KeyPrefix.claim) { return .claim(id: id) }
        if id.hasPrefix(KeyPrefix.lead) { return .lead(id: id) }
        return nil
    }

    /// Salesforce ids are 15 or 18 alphanumeric characters. Anything else is rejected before it
    /// reaches the API.
    static func isValidId(_ id: String) -> Bool {
        (id.count == 15 || id.count == 18) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
