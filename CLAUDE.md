# Wavetile

Native Jellyfin music + podcast player for iPhone (iOS 26.1+, Swift 6, SwiftUI). Bundle `com.derrellwilliams.wavetile`.

## Build & run
- `Wavetile.xcodeproj` is generated: edit `project.yml`, then `xcodegen generate` (also after adding/removing files in `App/`).
- Build: `xcodebuild -project Wavetile.xcodeproj -scheme Wavetile -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build`
- Run: `xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Wavetile.app && xcrun simctl launch booted com.derrellwilliams.wavetile [flags]`
- Tests: package scheme `WavetileKit-Package` (incl. a 50k-track perf suite); UI tests (incl. an accessibility audit) in `UITests/`, run from the `Wavetile` scheme.
- TestFlight: `scripts/testflight.sh` (no argument; build numbers are timestamps, so don't bump `CURRENT_PROJECT_VERSION`). Only when asked.
- Debug builds link with `-interposable` for hot reload (Inject); Release doesn't.

## Layout
| Path | What |
|---|---|
| `App/` | Thin app target |
| `Widgets/`, `Shared/` | Widget extension (Now Playing, Recently Played, download Live Activity); playback intents shared with the app |
| `site/` | Marketing site for wavetile.com (static, Vercel root directory `site`; see `site/README.md`) |
| `scripts/` | `testflight.sh`, `fetch-icons.sh` (adds Phosphor icons to the DesignSystem asset catalog) |
| `Packages/WavetileKit/Sources/JellyfinKit` | API client (jellyfin-sdk-swift), auth, Quick Connect, Keychain, Instant Mix |
| `Persistence` | GRDB library mirror; read queries in `Queries.swift`, `Genres.swift`, `Discovery.swift` |
| `Library` | Full library sync, record → UI mapping |
| `Playback` | `PlaybackQueue` + gapless `AudioPlayer` (AVQueuePlayer) |
| `Downloads` | Background downloads (MP3 256 kbps default, or Original) |
| `Podcasts` | Feeds, own GRDB db, directory search, chapters, transcripts, OPML, Jellyfin-synced subscriptions |
| `DesignSystem` | `Theme` tokens (Dark default, Light), `Glyph`, `Motion`, components |
| `WidgetShared` | Lightweight types for the widget extension (snapshots, command center, Live Activity attributes) |
| `PreviewSupport` | Preview fixtures |
| `Features` | Screens and view models, one folder per area. Tabs: Home, Music, Podcasts, Downloaded, Search; Settings is a side drawer |

## Home feed (`Features/Home`)
Shelves are read from the local DB on init (first frame, works offline), then `load()` refreshes the history shelves from the server once per session.
- History: Recently Played → Up Next in Podcasts (if enabled) → Most Played → Recently Added.
- New listener (`HomeModel.isNewListener`: < 6 albums in Recently Played): a welcome card (library counts and a nudge to start listening) on top, and 2 genre shelves (random from the 6 largest) + Playlists after Recently Added.
- Always at the bottom: From Your Library (16 random albums), then Artist Spotlight (random artist, preferring one with a photo and 3+ albums).
- Random picks change on launch and on pull to refresh, not on the server refresh. After the first library sync, `librarySynced()` fills empty shelves.

## Conventions
- Icons: Phosphor Bold via `Glyph` only. Never SF Symbols.
- Fonts: Familjen Grotesk for UI text and section headers; Stack Sans Notch for the wordmark and content titles (albums, artists, shows). No red in the brand.
- Match the surrounding code's comment style; screens observe GRDB via `store.observe(...)`.
- Song/album/artist actions (favorite, add to playlist, Start Radio = Jellyfin Instant Mix replacing the queue) live in `Features/Library/LibraryActions.swift`.
- Plain HTTP only to LAN hosts; `NSAllowsArbitraryLoadsInMedia` is for podcast audio only. Keep the token off cleartext.
- Swift 6: closures handed to MediaPlayer/AVFoundation must be built nonisolated.
- CarPlay (`Features/CarPlay`, `App/CarPlaySceneDelegate.swift`) needs Apple's `com.apple.developer.carplay-audio` entitlement added to `App/Wavetile.entitlements` once granted; until then CarPlay doesn't list the app on a device. Simulator builds use `App/Wavetile-Simulator.entitlements`, which already has it, so the CarPlay simulator (I/O → External Displays → CarPlay) works now. Siri phrases live in `App/MusicIntents.swift`.
- Debug launch flags (`DebugFlags` in `MainTabView.swift`, compiled out of Release): `-freshHome` (Home as a new listener sees it), `-tab <name>`, `-openSettings`, `-openFirstAlbum [-albumIndex N] [-autoplay] [-openNowPlaying] [-autodownload] [-openArtist]`, `-enablePodcasts`, `-followFeed <url>`, `-playLatestEpisode`, `-openLatestEpisode`.

## Git
Commit and push only when asked; always land on `main`.
