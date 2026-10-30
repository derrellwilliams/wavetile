import Foundation

/// How this app identifies itself to Jellyfin in the `Authorization: MediaBrowser ...` header.
public struct ClientIdentity: Sendable, Equatable {
    public var clientName: String
    public var version: String
    public var deviceName: String
    public var deviceID: String

    public init(clientName: String, version: String, deviceName: String, deviceID: String) {
        self.clientName = clientName
        self.version = version
        self.deviceName = deviceName
        self.deviceID = deviceID
    }

    /// Loads (or creates once) a stable per-install device ID from the Keychain.
    /// Jellyfin keys sessions by device ID, so it must not change between launches.
    public static func load(deviceName: String, keychain: Keychain = Keychain()) -> ClientIdentity {
        let account = "device-id"
        let deviceID: String
        do {
            if let existing = try keychain.string(for: account) {
                deviceID = existing
            } else {
                deviceID = UUID().uuidString
                try? keychain.set(deviceID, for: account)
            }
        } catch {
            // The Keychain couldn't be read (e.g. before first unlock after a reboot), which
            // isn't the same as no ID saved: use one for this launch only, and keep the real one.
            deviceID = UUID().uuidString
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return ClientIdentity(clientName: "Wavetile", version: version, deviceName: deviceName, deviceID: deviceID)
    }
}
