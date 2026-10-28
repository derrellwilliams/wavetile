import Foundation
import JellyfinKit
import Persistence

// Database records → UI models shared with API-backed screens.

public extension AlbumRecord {
    var summary: AlbumSummary {
        AlbumSummary(id: id, title: title, artist: artistName, year: year, imageTag: imageTag)
    }
}

public extension TrackRecord {
    var summary: TrackSummary {
        TrackSummary(
            id: id,
            title: title,
            artist: artistName,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: durationMs.map { .milliseconds($0) },
            normalizationGain: normalizationGain
        )
    }
}
