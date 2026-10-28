// "Play <album, artist or playlist> in Wavetile". App target only: an app has one
// AppShortcutsProvider, and the widget extension only needs the controls in Shared/.
import AppIntents
import Features

struct MusicItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Music"
    static let defaultQuery = MusicItemQuery()

    let id: String
    let title: String
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }

    init(_ item: SiriMusicItem) {
        id = item.key
        title = item.title
        subtitle = item.subtitle
    }
}

struct MusicItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MusicItemEntity] {
        (AppModel.current?.siriItems(keys: identifiers) ?? []).map(MusicItemEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [MusicItemEntity] {
        (AppModel.current?.siriSearch(string) ?? []).map(MusicItemEntity.init)
    }

    /// Also the names Siri learns for the spoken phrases below.
    @MainActor
    func suggestedEntities() async throws -> [MusicItemEntity] {
        (AppModel.current?.siriSuggestions() ?? []).map(MusicItemEntity.init)
    }
}

struct PlayMusicIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Music"
    static let description = IntentDescription("Plays an album, artist or playlist from your Jellyfin library.")

    @Parameter(title: "Music", requestValueDialog: "What would you like to play?")
    var item: MusicItemEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppModel.current?.playForSiri(item.id) == true else {
            return .result(dialog: "Couldn't play \(item.title).")
        }
        return .result(dialog: "Playing \(item.title).")
    }
}

struct WavetileShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMusicIntent(),
            phrases: [
                "Play \(\.$item) in \(.applicationName)",
                "Play \(\.$item) on \(.applicationName)",
                "Play music in \(.applicationName)",
            ],
            shortTitle: "Play Music",
            // The Shortcuts app only takes SF Symbol names here; it's never shown in Wavetile itself.
            systemImageName: "play.fill"
        )
    }
}
