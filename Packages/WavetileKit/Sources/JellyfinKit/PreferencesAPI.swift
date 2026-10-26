import Foundation

public extension LibraryClient {
    /// Wavetile's own client name for DisplayPreferences, so its keys never collide with
    /// Jellyfin Web or other apps.
    static let preferencesClient = "wavetile"

    /// Free-form per-user settings Jellyfin stores for a client (`DisplayPreferences.CustomPrefs`).
    func customPreferences(id: String) async throws -> [String: String] {
        let request = Paths.getDisplayPreferences(displayPreferencesID: id, userID: session.userID, client: Self.preferencesClient)
        return try await client.send(request).value.customPrefs ?? [:]
    }

    /// Replaces the custom preferences. The server overwrites the whole record on save, so the
    /// current record is read first and only `customPrefs` changes.
    func saveCustomPreferences(_ prefs: [String: String], id: String) async throws {
        let get = Paths.getDisplayPreferences(displayPreferencesID: id, userID: session.userID, client: Self.preferencesClient)
        var record = try await client.send(get).value
        record.customPrefs = prefs
        record.client = Self.preferencesClient
        let save = Paths.updateDisplayPreferences(displayPreferencesID: id, userID: session.userID, client: Self.preferencesClient, record)
        try await client.send(save)
    }
}
