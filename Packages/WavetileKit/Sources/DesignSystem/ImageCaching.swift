import Foundation
import Nuke
import UIKit

/// Image pipeline with a persistent on-disk cache, so artwork for downloaded music shows offline
/// and scrolling never re-downloads art. Call once at launch, before any image loads.
public enum ImageCaching {
    /// Idempotent: replacing the shared pipeline while requests are in flight would orphan them.
    @MainActor public static func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        var configuration = ImagePipeline.Configuration.withDataCache(
            name: "com.derrellwilliams.wavetile.artwork",
            sizeLimit: 1024 * 1024 * 1024
        )
        configuration.isProgressiveDecodingEnabled = false
        // Security: podcast art comes from any host a feed names, so no cookies go to or from them.
        let session = URLSessionConfiguration.default
        session.urlCache = nil
        session.httpCookieAcceptPolicy = .never
        session.httpShouldSetCookies = false
        configuration.dataLoader = DataLoader(configuration: session)
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }

    /// Removes all cached artwork, in memory and on disk (sign out: it belongs to that account).
    @MainActor public static func removeAll() {
        ImagePipeline.shared.cache.removeAll()
    }

    @MainActor private static var isConfigured = false

    /// One image, from the cache when it's there (CarPlay list artwork).
    public static func image(for url: URL) async -> UIImage? {
        try? await ImagePipeline.shared.image(for: url)
    }

    /// Prefetchers in flight; each is released when it finishes (deallocating one cancels its work).
    @MainActor private static var active: [ObjectIdentifier: ImagePrefetcher] = [:]

    /// Warms the disk cache (e.g. artwork sizes used by a downloaded album).
    @MainActor public static func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let prefetcher = ImagePrefetcher(pipeline: .shared, destination: .diskCache)
        let id = ObjectIdentifier(prefetcher)
        active[id] = prefetcher
        prefetcher.didComplete = { active[id] = nil }
        prefetcher.startPrefetching(with: urls)
    }
}
