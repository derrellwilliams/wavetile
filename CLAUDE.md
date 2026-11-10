# Wavetile

Native Jellyfin music + podcast player for iPhone (iOS 26.1+, Swift 6, SwiftUI). Bundle `com.derrellwilliams.wavetile`.

## Build & run
- `Wavetile.xcodeproj` is generated: edit `project.yml`, then `xcodegen generate` (also after adding/removing files in `App/`).
- `.claude/settings.json` lets Claude run the build, test, `xcresulttool`, `xcodegen generate` and everyday `simctl` commands below without a prompt. `simctl spawn` is allowed only for `spawn booted log ...`; any other `spawn` asks, because it runs a process outside the sandbox. TestFlight archive and export still ask.
- Feature development: use the Xcode MCP (`xcode` server, needs Xcode running with `Wavetile.xcodeproj` open) for building (`BuildProject`), running (`RunProject`), previews (`RenderPreview`), tests (`RunSomeTests`, `RunAllTests`), build logs and issue checks (`GetBuildLog`, `XcodeRefreshCodeIssuesInFile`), and docs search (`DocumentationSearch`). Run `xcodegen generate` first when `project.yml` or the files in `App/` changed. The `xcodebuild`/`xcrun simctl` commands below are the fallback (Xcode not running, background UI test runs) and are still how TestFlight archives are made.
- Build (fallback): `xcodebuild -project Wavetile.xcodeproj -scheme Wavetile -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath build build`
- Run (two separate commands; an `&&` chain keeps them in the sandbox, where they fail): `xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Wavetile.app`, then `xcrun simctl launch booted com.derrellwilliams.wavetile [flags]`
- Check the screen: `xcrun simctl io booted screenshot <path>.png`, then read the PNG.
- Tests: package scheme `WavetileKit-Package` (incl. a 50k-track perf suite); UI tests (incl. an accessibility audit) in `UITests/`, run from the `Wavetile` scheme. Claude can run both; use `-derivedDataPath <repo>/build -quiet 2>&1`, one plain command each (a pipe or `$(...)` falls back into the sandbox and fails):
  - Package: `cd <repo>/Packages/WavetileKit` as its own command (the scheme only exists there), then `xcodebuild test -scheme WavetileKit-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' ...` (~30 s).
  - UI: `xcodebuild test -project <repo>/Wavetile.xcodeproj -scheme Wavetile -destination ... ...` takes ~5 min, past the 10-minute foreground limit if the machine is busy, so run it in the background.
  - `-quiet` hides results. Read them with `xcrun xcresulttool get test-results summary --path <repo>/build/Logs/Test/<newest>.xcresult` and check `runtimeWarnings` as well as failures (SwiftUI warnings such as "Accessing Environment outside of a View" show up only there). To find a warning's source: `xcrun simctl spawn booted log stream --backtrace --predicate 'eventMessage CONTAINS "<text>"'` in the background while launching the app, then `atos -o build/Build/Products/Debug-iphonesimulator/Wavetile.app/Wavetile.debug.dylib -arch arm64 -l 0x0 <offsets>`.
- TestFlight (only when asked): the steps are in `.claude/skills/testflight/SKILL.md` (`/testflight`). Read it first; archive and export still ask for approval.
- Debug builds link with `-interposable` for hot reload (Inject); Release doesn't.

## Layout
| Path | What |
|---|---|
| `App/` | Thin app target |
| `Widgets/`, `Shared/` | Widget extension (Now Playing, Recently Played, download Live Activity); playback intents shared with the app |
| `site/` | Marketing site for wavetile.com (static, Vercel root directory `site`; see `site/README.md`) |
| `scripts/` | `testflight.sh`, `fetch-icons.sh` (adds Phosphor icons to the DesignSystem asset catalog), `design-system.py` (writes the gallery) |
| `docs/` | `design-system.html` (the generated design system gallery), `LAUNCH.md` (release plan), `qa-evidence.md` (dated QA records), `search-optimization.md` (ASO, SEO, GEO) |
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

## Design system
`DesignSystem/` is the single source of truth for how the app looks; `docs/design-system.html` is its gallery, the reference for every token, icon and component.
- The gallery is generated, never hand-edited: `scripts/design-system.py` reads `Theme.swift` (palette, type, spacing, radius, artwork), `Motion.swift`, `Glyph.swift` with the `Icons.xcassets` SVGs, and `DesignSystem/Components`. It also scans the app's Swift files for each item's "Used in" list (file, line, code). Descriptions are the code's `///` doc comments, so document a token where it's defined.
- Changing the system: edit the token in code → run `scripts/design-system.py` → check the gallery (and the sim) → commit the code and the regenerated HTML together. `scripts/design-system.py --check` exits 1 if the page is stale.
- Views read tokens via `@Environment(\.theme)` (widgets: `Theme.dark`); don't add literal sizes, spacing, radii or hex colors to views. Type sizes live only in `Theme.Typography.scale`; the theme's fonts reference it. A new value goes into `Theme` first, with a doc comment.
- An item showing "No direct references found" is unused (or used in a way the scan doesn't match); confirm with the build before deleting it.

## Home feed (`Features/Home`)
Shelves are read from the local DB on init (first frame, works offline), then `load()` refreshes the history shelves from the server. Pull to refresh syncs music and enabled podcast feeds first; launch and foreground do the same when stale (>1h).
- Order: Recently Played → Most Played → Latest Podcast Episodes (if enabled) → Playlists & Collections → Recently Added → up to 3 Artist Spotlights. A new listener (`HomeModel.isNewListener`) also gets a first-visit welcome card on top and 2 genre shelves after Recently Added. Offline puts the offline notice and a Downloaded row first.
- Recommended for You (`PodcastRecommender`) is a shelf on the Podcasts tab under Latest Episodes, not on Home: scoring and caching are documented in `Podcasts/Recommendations.swift`. Only show titles and genre IDs may leave the device.
- Random picks change on launch and pull to refresh, not on the server refresh.

## Conventions
- Icons: Phosphor Bold via `Glyph` only. Never SF Symbols.
- Type: Inter Regular and Geist Mono Regular only, regular weight for text (hierarchy is size, color and mono); the playback-speed control is the one Geist Mono Bold. Seven sizes in `Theme.Typography.scale`; use the theme tokens. Metadata (years, counts, durations, times, dates, sizes) is mono via `itemMetadata` or `typography.mono(_:)`; names under an item (artist, author) are Inter via `itemSubtitle`. Bar titles and tab labels are styled in `applyNavigationBarAppearance` (SwiftUI's per-bar appearances ignore the proxy, so the back-chevron controller in `MainTabView.swift` copies titles onto them). No red in the brand.
- Logo: the wave (`WaveMark`) is centered in Home's top bar and is the sign-in mark; Home has no on-screen title. Tabs are icon only, and Home's is the cube (`WavetileMark`, also `LoadingMark` and pull to refresh). `App/Assets.xcassets/LaunchSplash` is `SplashScreen`'s first frame, rendered from the same `Lockup` numbers; re-render it if they change.
- Match the surrounding code's comment style; screens observe GRDB via `store.observe(...)`.
- Bar buttons hide the bar's glass and draw their own (`TintedBar.drawsGlass`; the types are in `MainTabView.swift`). Keep the system Back, drawn tinted; never hide it for a custom one (on iOS 27 that kills the swipe back inside UIKit, past any gesture delegate).
- Song/album/artist actions (favorite, add to playlist, Start Radio = Jellyfin Instant Mix replacing the queue) live in `Features/Library/LibraryActions.swift`.
- Offline (`Features/Downloads/Offline.swift`): every main tab shows `OfflineNotice` under its title; song rows (`PlayableRow`) and album/playlist/collection tiles (`offlineDimmed(available:)`) dim what isn't downloaded; actions that change the library on the server use `requiresServer()`. Podcasts only count a lost network, since episodes stream from their feeds.
- Plain HTTP only to LAN hosts; `NSAllowsArbitraryLoadsInMedia` is for podcast audio only. Keep the token off cleartext.
- Swift 6: closures handed to MediaPlayer/AVFoundation must be built nonisolated.
- CarPlay (`Features/CarPlay`, `App/CarPlaySceneDelegate.swift`) uses the `com.apple.developer.carplay-audio` entitlement (set in `project.yml`, which writes `App/Wavetile.entitlements`). Device signing needs CarPlay Audio enabled on the App ID. Test with the CarPlay simulator (I/O → External Displays → CarPlay). Siri phrases live in `App/MusicIntents.swift`.
- Account data lifecycle: sign-out (`AppModel.signOut`) stops each store (`LibraryStore.shutdown()`, `PodcastsStore.shutdown()`: cancel and await running work, close the pool), and only then deletes databases and files; credentials are cleared last. New background work in a store must stop at its shutdown flag, and nothing may write to a database after sign-out. A stand-in database (`isTemporary`, used when the real one won't open) gets no download managers, because they delete finished files that have no row.
- Server data is untrusted for destructive steps: anything that replaces or prunes cached or server data (playlist and collection membership, library prune, collection rename) reads every page through `completeItems` and fails closed on a missing `Items` or total; a feed that didn't parse to the end (`ParsedFeed.isComplete == false`) never prunes episodes; an unreadable synced subscription list is ignored, not treated as empty; a library mirror with no songs at all never removes or shrinks a download (`syncedDownloadSource`). Numbers from feeds, chapters and the synced podcast record are range-checked before use (`FeedParser.maxDuration`, `PodcastSyncState.isPlausibleDate`): never convert one to `Int` or `Duration` unchecked.
- Siri's spoken names refresh through `AppModel.onLibraryVocabularyChanged` (after a sync, sign-in and sign-out); widgets and download Live Activities are cleared and ended at sign-out.
- Debug launch flags (`DebugFlags` in `MainTabView.swift`, compiled out of Release; the doc comments list them all). Most useful: `-freshHome` (Home as a new listener sees it), `-tab <name>`, `-openFirstAlbum [-autoplay]`, `-enablePodcasts`, `-followFeed <url>`.

## Release planning
- `docs/LAUNCH.md` is the working checklist for engineering QA, App Store readiness, launch and follow-up. User device checks were signed off by the tester on 2026-11-08 (build 202611072135); record any new ones in LAUNCH.md. Read these when resuming release work and update dated status in the appropriate file; dated engineering QA evidence goes in `docs/qa-evidence.md`, ASO/SEO/GEO notes live in `docs/search-optimization.md`.

## Git
Commit and push only when asked. When asked, the work lands on `main` (merge any branch into it) and `main` is pushed.
