import Testing
@testable import JellyfinKit

struct ServerAddressTests {
    @Test func bareHostDefaultsToHTTPS() throws {
        let address = try ServerAddress("music.example.com/")
        #expect(address.url.absoluteString == "https://music.example.com")
        #expect(address.transportWarning == nil)
    }

    @Test func keepsPortAndPath() throws {
        let address = try ServerAddress("  http://192.168.1.20:8096/jellyfin/  ")
        #expect(address.url.absoluteString == "http://192.168.1.20:8096/jellyfin")
    }

    @Test(arguments: ["", "   ", "ftp://host", "https://"])
    func rejectsInvalid(_ input: String) {
        #expect(throws: ServerAddress.InputError.self) { try ServerAddress(input) }
    }

    @Test(arguments: [
        ("http://10.0.0.4:8096", true),
        ("http://172.20.1.1", true),
        ("http://172.32.1.1", false),
        ("http://192.168.0.2", true),
        ("http://nas.local:8096", true),
        ("http://localhost:8096", true),
        ("http://10.1.2.3.nip.io", false),
        ("http://fdroid.example.com", false),
        ("http://music.example.com", false),
        ("http://100.101.102.103:8096", true),
        ("http://100.63.0.1", false),
        ("http://100.128.0.1", false),
        ("http://nas.tail1234.ts.net:8096", true),
        ("http://ts.net.example.com", false),
    ])
    func classifiesLocalNetwork(_ input: String, isLocal: Bool) throws {
        #expect(try ServerAddress(input).isLocalNetwork == isLocal)
    }

    @Test func warnsOnRemoteHTTP() throws {
        #expect(try ServerAddress("http://music.example.com").transportWarning == .insecureRemote)
        #expect(try ServerAddress("http://192.168.1.2").transportWarning == .insecureLocal)
    }
}

struct ServerAddressCandidateTests {
    @Test func defaultJellyfinPortTriesHTTPFirst() throws {
        let urls = try ServerAddress.candidates(for: "192.168.86.27:8096").map(\.url.absoluteString)
        #expect(urls == ["http://192.168.86.27:8096", "https://192.168.86.27:8096"])
    }

    @Test func localHostTriesHTTPSFirst() throws {
        let urls = try ServerAddress.candidates(for: "nas.local").map(\.url.absoluteString)
        #expect(urls == ["https://nas.local", "http://nas.local"])
    }

    @Test func remoteHostNeverFallsBackToHTTP() throws {
        let urls = try ServerAddress.candidates(for: "music.example.com:8096").map(\.url.absoluteString)
        #expect(urls == ["https://music.example.com:8096"])
    }

    @Test func explicitSchemeIsRespected() throws {
        let urls = try ServerAddress.candidates(for: "https://192.168.1.2:8920").map(\.url.absoluteString)
        #expect(urls == ["https://192.168.1.2:8920"])
    }
}
