import Foundation
import Observation

/// What the person searched for, newest first, shown when the search field is empty. A query
/// counts once it's submitted or a result is opened or played, so half-typed text isn't kept.
/// Device-only (UserDefaults), and cleared on sign-out with the rest of the account's data.
@MainActor @Observable
final class RecentSearches {
    private static let key = "recentSearches"
    private static let limit = 10

    private(set) var queries: [String] {
        didSet { UserDefaults.standard.set(queries, forKey: Self.key) }
    }

    init() {
        queries = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Moves `query` to the top, replacing an earlier entry that differs only in case.
    func add(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var updated = queries.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        updated.insert(query, at: 0)
        queries = Array(updated.prefix(Self.limit))
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
    }

    func clear() {
        queries = []
    }

    static func clearStored() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
