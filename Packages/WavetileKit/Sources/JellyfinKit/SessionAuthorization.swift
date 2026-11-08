import Foundation
import os

/// Shared by the account's clients so reauthentication updates credentials without rebuilding
/// databases, playback or background-download managers. Old responses cannot reject a new token.
public final class SessionAuthorization: Sendable {
    private struct State {
        var token: String
        var rejected = false
    }
    private let state: OSAllocatedUnfairLock<State>
    private let onUnauthorized: @Sendable () -> Void

    public init(token: String, onUnauthorized: @escaping @Sendable () -> Void) {
        state = OSAllocatedUnfairLock(initialState: State(token: token))
        self.onUnauthorized = onUnauthorized
    }

    public var isRejected: Bool { state.withLock { $0.rejected } }

    public var token: String { state.withLock { $0.token } }

    public func replaceToken(_ token: String) {
        state.withLock { $0 = State(token: token) }
    }

    public func reject(token: String) {
        let notify = state.withLock { state in
            guard state.token == token, !state.rejected else { return false }
            state.rejected = true
            return true
        }
        if notify { onUnauthorized() }
    }
}
