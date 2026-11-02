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
| `scripts/` | `testflight.sh`, `fetch-icons.sh` (adds Phosphor icons to the DesignSystem asset catalog), `design-system.py` (writes the gallery) |
| `docs/` | `design-system.html`, the generated design system gallery |
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
Shelves are read from the local DB on init (first frame, works offline), then `load()` refreshes the history shelves from the server once per session.
- History: Recently Played → Latest Podcast Episodes (if enabled) → Most Played → Recently Added.
- New listener (`HomeModel.isNewListener`: < 6 albums in Recently Played): a welcome card (library counts and a nudge to start listening) on top for the first visit only (`showsWelcome`; a visit counts after a minute on Home), and 2 genre shelves (random from the 6 largest) + Playlists after Recently Added.
- Always at the bottom: up to 3 Artist Spotlights (random artists with 3+ albums, ones with a photo first; none if no artist qualifies).
- Random picks change on launch and on pull to refresh, not on the server refresh. After the first library sync, `librarySynced()` fills empty shelves.

## Conventions
- Icons: Phosphor Bold via `Glyph` only. Never SF Symbols.
- Type: Inter Regular and Geist Mono Regular only, one weight (never `.weight`/bold; hierarchy is size, color and mono). Seven sizes, `Theme.Typography.scale`: 12 caption · 14 item · 16 body · 18 large · 20 section/lead · 22 title · 36 screen/detail title. Use the theme tokens; metadata (years, counts, durations, times, dates, sizes) is mono via `itemMetadata` or `typography.mono(_:)`; names under an item (artist, author) are Inter via `itemSubtitle`. `BrandFont`'s bare text styles map onto the scale, RootView sets Inter body as the default font, and `applyNavigationBarAppearance` styles bar titles (36 large, with `largeTitlePadding`) and tab labels (SwiftUI's per-bar appearances ignore the proxy, so the back-chevron controller in `MainTabView.swift` copies titles onto them). No red in the brand.
- Logo: the wave (`WaveMark`, from wave.svg) is centered in Home's top bar (`tabRootChrome(showsWave:)`; Home has no on-screen title) and is the sign-in mark. Tabs are icon only; Home's tab icon is the cube (`WavetileMark.uiImage`). The cube (`WavetileMark`) is `LoadingMark` and pull to refresh. The splash (`SplashScreen`, from loading.svg) is the turning cube over "Wavetile" (Inter Regular) over the rippling wave, cube and wave at the same stroke. `App/Assets.xcassets/LaunchSplash` is its first frame (460 × 1000pt, centered), rendered from the same `Lockup` numbers so launch hands off without a jump; re-render it if they change.
- Match the surrounding code's comment style; screens observe GRDB via `store.observe(...)`.
- Bar buttons are tinted fills covering the bar's glass, leaving its faint rim (iOS keeps glass behind the system Back and ignores `hidesSharedBackground` there, so every button matches it; the fill is `TintedBar.glassInset` wider than the item; iOS 26 clips items to their frame, so there `TintedBar.fillsGlass` is false: no overhang and the bar's glass is hidden behind them): `TintedBarIcon`, `TintedBarCapsule`/`TintedBarGroup`, `TintedSheetButton`, `listBar`/`detailBarButtons` (all in `MainTabView.swift`). Keep the system Back, drawn tinted; never hide it for a custom one (on iOS 27 that kills the swipe back inside UIKit, past any gesture delegate).
- Song/album/artist actions (favorite, add to playlist, Start Radio = Jellyfin Instant Mix replacing the queue) live in `Features/Library/LibraryActions.swift`.
- Plain HTTP only to LAN hosts; `NSAllowsArbitraryLoadsInMedia` is for podcast audio only. Keep the token off cleartext.
- Swift 6: closures handed to MediaPlayer/AVFoundation must be built nonisolated.
- CarPlay (`Features/CarPlay`, `App/CarPlaySceneDelegate.swift`) uses the `com.apple.developer.carplay-audio` entitlement (granted 2026-10-30; set in `project.yml`, which writes `App/Wavetile.entitlements`). Device signing needs CarPlay Audio enabled on the App ID. Test with the CarPlay simulator (I/O → External Displays → CarPlay). Siri phrases live in `App/MusicIntents.swift`.
- Debug launch flags (`DebugFlags` in `MainTabView.swift`, compiled out of Release): `-freshHome` (Home as a new listener sees it), `-tab <name>`, `-openSettings`, `-openFirstAlbum [-albumIndex N] [-autoplay] [-openNowPlaying] [-autodownload] [-openArtist]`, `-tab music -openSection <albums|songs|playlists|…>`, `-enablePodcasts`, `-followFeed <url>`, `-playLatestEpisode`, `-openLatestEpisode`.

## Git
Commit and push only when asked; always land on `main`.
