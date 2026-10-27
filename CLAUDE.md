# Wavetile

Native Jellyfin music + podcast player for iPhone (iOS 26.1+, Swift 6, SwiftUI). Bundle `com.derrellwilliams.wavetile`.

## Build & run
- `Wavetile.xcodeproj` is generated: edit `project.yml`, then `xcodegen generate` (also after adding/removing files in `App/`).
- Build: `xcodebuild -project Wavetile.xcodeproj -scheme Wavetile -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build`
- Run: `xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Wavetile.app && xcrun simctl launch booted com.derrellwilliams.wavetile [flags]`
- Tests: package scheme `WavetileKit-Package` (incl. a 50k-track perf suite); UI tests in `UITests/`.
- TestFlight: `scripts/testflight.sh` (no argument; build numbers are timestamps). Only when asked.

## Layout
| Path | What |
|---|---|
| `App/` | Thin app target |
| `Widgets/`, `Shared/` | Widget extension (Now Playing, Recently Played, download Live Activity); intents shared with the app |
| `Packages/WavetileKit/Sources/JellyfinKit` | API client (jellyfin-sdk-swift), auth, Quick Connect |
| `Persistence` | GRDB library mirror; read queries in `Queries.swift`, `Genres.swift`, `Discovery.swift` |
| `Library` | Full library sync, record → UI mapping |
| `Playback` | `PlaybackQueue` + gapless `AudioPlayer` (AVQueuePlayer) |
| `Downloads` | Background downloads (MP3 default) |
| `Podcasts` | Feeds, own GRDB db, directory search, chapters, Jellyfin-synced subscriptions |
| `DesignSystem` | `Theme` tokens (Dark default, Light), `Glyph`, `Motion`, components |
| `Features` | Screens and view models, one folder per area |

## Home feed (`Features/Home`)
Shelves are read from the local DB on init (first frame, works offline), then `load()` refreshes the history shelves from the server once per session.
- History: Recently Played → Up Next in Podcasts (if enabled) → Most Played → Recently Added.
- New listener (`HomeModel.isNewListener`: < 6 albums in Recently Played): a welcome card (library counts, Shuffle All, Genres) on top, and 2 genre shelves (random from the 6 largest) + Playlists after Recently Added.
- Always at the bottom: From Your Library (16 random albums), then Artist Spotlight (random artist, preferring one with a photo and 3+ albums).
- Random picks change on launch and on pull to refresh, not on the server refresh. After the first library sync, `librarySynced()` fills empty shelves.

## Conventions
- Icons: Phosphor Bold via `Glyph` only. Never SF Symbols.
- Fonts: Familjen Grotesk for UI text and section headers; Stack Sans Notch for the wordmark and content titles (albums, artists, shows). No red in the brand.
- Match the surrounding code's comment style; screens observe GRDB via `store.observe(...)`.
- Swift 6: closures handed to MediaPlayer/AVFoundation must be built nonisolated.
- Debug launch flags (`DebugFlags` in `MainTabView.swift`, compiled out of Release): `-freshHome` (Home as a new listener sees it), `-tab <name>`, `-openSettings`, `-openFirstAlbum [-albumIndex N] [-autoplay] [-openNowPlaying] [-autodownload]`, `-enablePodcasts`, `-followFeed <url>`, `-playLatestEpisode`, `-openLatestEpisode`.

## Git
Commit and push only when asked; always land on `main`.
