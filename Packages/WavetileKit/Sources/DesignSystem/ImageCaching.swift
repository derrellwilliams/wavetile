import Foundation
import Nuke

/// Image pipeline with a persistent on-disk cache, so artwork for downloaded music shows offline
/// and scrolling never re-downloads art. Call once at launch, before any image loads.
public enum ImageCaching {
    public static func configure() {
        var configuration = ImagePipeline.Configuration.withDataCache(
            name: "com.derrellwilliams.wavetile.artwork",
            sizeLimit: 1024 * 1024 * 1024
        )
        configuration.isProgressiveDecodingEnabled = false
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }

    /// Warms the disk cache (e.g. artwork sizes used by a downloaded album).
    public static func prefetch(_ urls: [URL]) {
        let prefetcher = ImagePrefetcher(pipeline: .shared, destination: .diskCache)
        prefetcher.startPrefetching(with: urls)
        // Keep the prefetcher alive until requests are issued.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { _ = prefetcher }
    }
}
