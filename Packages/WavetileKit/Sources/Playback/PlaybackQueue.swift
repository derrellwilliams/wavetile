import Foundation

/// Where a podcast episode's audio and art live. Podcast hosts are third parties: these URLs
/// are fetched without the Jellyfin token.
public struct PodcastMedia: Hashable, Sendable {
    public var audioURL: URL
    public var artworkURL: URL?

    public init(audioURL: URL, artworkURL: URL?) {
        self.audioURL = audioURL
        self.artworkURL = artworkURL
    }
}

/// A track in the play queue. `queueID` is unique per entry, so the same song can be queued twice.
///
/// Podcast episodes use the same type: `trackID` is the episode ID, `artist` the show's author,
/// `albumTitle` the show, and `podcast` says where to stream from.
public struct QueuedTrack: Identifiable, Hashable, Sendable {
    public let queueID: UUID
    public let trackID: String
    public var title: String
    public var artist: String
    public var albumTitle: String
    public var albumID: String?
    public var albumImageTag: String?
    public var duration: Duration?
    public var podcast: PodcastMedia?

    public var id: UUID { queueID }
    public var isEpisode: Bool { podcast != nil }

    public init(
        trackID: String, title: String, artist: String, albumTitle: String,
        albumID: String?, albumImageTag: String? = nil, duration: Duration?, podcast: PodcastMedia? = nil
    ) {
        self.queueID = UUID()
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.albumID = albumID
        self.albumImageTag = albumImageTag
        self.duration = duration
        self.podcast = podcast
    }

    /// Same song, new queue entry.
    public func requeued() -> QueuedTrack {
        QueuedTrack(trackID: trackID, title: title, artist: artist, albumTitle: albumTitle,
                    albumID: albumID, albumImageTag: albumImageTag, duration: duration, podcast: podcast)
    }
}

public enum RepeatMode: String, Sendable, CaseIterable {
    case off, all, one
}

/// Pure play-queue logic (no audio), so ordering rules are unit-testable.
///
/// `items` is the play order; `index` points at the current track. Shuffle reorders only the
/// upcoming tracks and remembers the original order so turning it off restores it.
public struct PlaybackQueue: Sendable, Equatable {
    public private(set) var items: [QueuedTrack] = []
    public private(set) var index = 0
    public var repeatMode: RepeatMode = .off
    public private(set) var isShuffled = false
    private var originalOrder: [UUID] = []

    public init() {}

    public init(tracks: [QueuedTrack], startAt start: Int = 0, shuffled: Bool = false) {
        items = tracks
        index = tracks.indices.contains(start) ? start : 0
        originalOrder = tracks.map(\.queueID)
        if shuffled { setShuffle(true) }
    }

    public var current: QueuedTrack? { items.indices.contains(index) ? items[index] : nil }
    public var isEmpty: Bool { items.isEmpty }
    public var upNext: ArraySlice<QueuedTrack> { items.indices.contains(index) ? items[(index + 1)...] : [] }

    /// Track that will play after the current one finishes on its own (respects repeat).
    public var automaticNext: QueuedTrack? {
        switch repeatMode {
        case .one: current
        case .all: items.indices.contains(index + 1) ? items[index + 1] : items.first
        case .off: items.indices.contains(index + 1) ? items[index + 1] : nil
        }
    }

    /// Advance when the current track ends by itself. Returns false when playback should stop.
    public mutating func advanceAutomatically() -> Bool {
        switch repeatMode {
        case .one: return true
        case .all:
            guard !items.isEmpty else { return false }
            index = (index + 1) % items.count
            return true
        case .off:
            guard items.indices.contains(index + 1) else { return false }
            index += 1
            return true
        }
    }

    /// User pressed Next: always moves on (wrapping with repeat-all), ignoring repeat-one.
    public mutating func skipForward() -> Bool {
        if items.indices.contains(index + 1) {
            index += 1
            return true
        }
        guard repeatMode == .all, !items.isEmpty else { return false }
        index = 0
        return true
    }

    public mutating func skipBackward() -> Bool {
        if index > 0 {
            index -= 1
            return true
        }
        guard repeatMode == .all, !items.isEmpty else { return false }
        index = items.count - 1
        return true
    }

    public mutating func jump(to queueID: UUID) {
        if let target = items.firstIndex(where: { $0.queueID == queueID }) { index = target }
    }

    public mutating func playNext(_ tracks: [QueuedTrack]) {
        let at = items.isEmpty ? 0 : index + 1
        items.insert(contentsOf: tracks, at: at)
        // In the original order they also go right after the current track.
        let anchor = current.flatMap { originalOrder.firstIndex(of: $0.queueID) }.map { $0 + 1 } ?? originalOrder.count
        originalOrder.insert(contentsOf: tracks.map(\.queueID), at: min(anchor, originalOrder.count))
    }

    public mutating func append(_ tracks: [QueuedTrack]) {
        items.append(contentsOf: tracks)
        originalOrder.append(contentsOf: tracks.map(\.queueID))
    }

    public mutating func remove(_ queueID: UUID) {
        guard let target = items.firstIndex(where: { $0.queueID == queueID }), target != index else { return }
        items.remove(at: target)
        if target < index { index -= 1 }
        originalOrder.removeAll { $0 == queueID }
    }

    /// Reorders within Up Next. Offsets are relative to `upNext`.
    public mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI.
        var upcoming = Array(upNext)
        let moving = source.map { upcoming[$0] }
        let insertAt = destination - source.count(in: 0 ..< destination)
        for offset in source.reversed() { upcoming.remove(at: offset) }
        upcoming.insert(contentsOf: moving, at: insertAt)
        items.replaceSubrange((index + 1)..., with: upcoming)
    }

    public mutating func setShuffle(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        guard let current else { return }
        if on {
            var upcoming = items.filter { $0.queueID != current.queueID }
            upcoming.shuffle()
            items = [current] + upcoming
            index = 0
        } else {
            let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.queueID, $0) })
            items = originalOrder.compactMap { byID[$0] }
            index = items.firstIndex { $0.queueID == current.queueID } ?? 0
        }
    }

    public mutating func cycleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
