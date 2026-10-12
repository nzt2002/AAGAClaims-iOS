import Foundation

public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value, at: Date)
    case failed(PortalAPIError)

    public var value: Value? {
        if case .loaded(let value, _) = self { return value }
        return nil
    }

    public var loadedAt: Date? {
        if case .loaded(_, let date) = self { return date }
        return nil
    }

    public var error: PortalAPIError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Data is refreshed on returning to the foreground once it's more than 5 minutes old (spec §7).
    public static var staleAfter: TimeInterval { 5 * 60 }

    /// True when loaded more than `staleAfter` ago, or when the last load failed.
    public func isStale(now: Date = Date()) -> Bool {
        switch self {
        case .loaded(_, let at): now.timeIntervalSince(at) > Self.staleAfter
        case .failed: true
        case .idle, .loading: false
        }
    }
}

extension PortalAPIError {
    /// Wraps any error from a `PortalAPI` call. Never exposes server text (spec §7).
    static func wrap(_ error: Error) -> PortalAPIError {
        if let portalError = error as? PortalAPIError { return portalError }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(urlError.code) {
            return .offline
        }
        return .server(status: 0)
    }
}

/// Loads a value once, keeping the previous value on screen during a refresh.
@MainActor
func load<Owner: AnyObject, Value: Sendable>(
    _ owner: Owner,
    _ keyPath: ReferenceWritableKeyPath<Owner, LoadState<Value>>,
    _ fetch: () async throws -> Value
) async {
    if owner[keyPath: keyPath].value == nil {
        owner[keyPath: keyPath] = .loading
    }
    do {
        owner[keyPath: keyPath] = .loaded(try await fetch(), at: Date())
    } catch is CancellationError {
        // A newer refresh replaced this one; leave the state alone.
    } catch {
        owner[keyPath: keyPath] = .failed(.wrap(error))
    }
}
