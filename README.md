# Wavetile

**Your Jellyfin music and your podcasts, in one app.** Wavetile is a native iPhone client for Jellyfin (iOS 26.1+) with a full podcast player built in.

**Public beta:** [join on TestFlight](https://testflight.apple.com/join/pk9dyfMq) · [wavetile.com](https://wavetile.com) · [download and setup guide](https://wavetile.com/getting-started) · [support](https://wavetile.com/support)

You need an iPhone on iOS 26.1 or later and a Jellyfin server with a music library. Wavetile collects no data: no account, no analytics, no tracking ([privacy policy](https://wavetile.com/privacy)). Bug reports and feature ideas are welcome in [Issues](https://github.com/derrellwilliams/wavetile/issues).

<img width="3241" height="1488" alt="wavetile" src="https://github.com/user-attachments/assets/4cfb75fe-5376-4a5d-8e44-516eff4793bf" />

## Features
| Area | What |
|---|---|
| Sign in | Server address or Quick Connect; token kept in the Keychain |
| Library | Full sync into a local GRDB mirror (fast and works offline): albums, artists, songs, genres, playlists, collections, favorites, search |
| Home | Recently Played, Most Played, Recently Added, From Your Library, Artist Spotlight; a welcome card plus genre and playlist shelves for new listeners |
| Playback | Gapless queue, shuffle/repeat, lock screen and Control Center controls, Start Radio (Jellyfin Instant Mix) |
| Downloads | Background downloads of albums and playlists (MP3 256 kbps by default, or the original file) |
| Podcasts | Opt-in in Settings: directory search, follow by URL or OPML, chapters, transcripts, episode downloads, subscriptions synced through Jellyfin |
| System | Now Playing and Recently Played widgets, download Live Activity, Siri, CarPlay (waiting on Apple's entitlement) |
| Themes | Dark (default) and Light |

## Setup
Requires Xcode 26 and iOS 26.1+ (iPhone only).
```sh
brew install xcodegen
xcodegen generate        # re-run after adding/removing files in App/ or changing project.yml
open Wavetile.xcodeproj
```
`Wavetile.xcodeproj` is generated from `project.yml`. Edit the spec, not the project.

| Task | Command |
|---|---|
| Build | `xcodebuild -project Wavetile.xcodeproj -scheme Wavetile -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build` |
| Package tests | Scheme `WavetileKit-Package` (includes a 50k-track performance suite) |
| UI tests | `UITests/`, run from the `Wavetile` scheme |
| TestFlight | `scripts/testflight.sh` (build number defaults to a timestamp) |
| New icon | Add the Phosphor name to `scripts/fetch-icons.sh` and run it |

## Layout
| Path | What |
|---|---|
| `App/` | Thin app target (`@main`, assets, CarPlay scene, Siri intents) |
| `Widgets/`, `Shared/` | Widget extension; playback intents shared with the app |
| `UITests/` | UI and accessibility audit tests |
| `Packages/WavetileKit/Sources/JellyfinKit` | API client, auth, Quick Connect, Keychain |
| `…/Persistence` | GRDB library database and queries |
| `…/Library` | Library sync and record → UI mapping |
| `…/Playback` | Play queue and gapless audio player |
| `…/Downloads` | Background download manager |
| `…/Podcasts` | Feeds, podcast database, directory search, chapters, transcripts, OPML |
| `…/DesignSystem` | Theme tokens, icons, motion, components |
| `…/WidgetShared` | Lightweight types shared with the widget extension |
| `…/PreviewSupport` | Fixtures for previews |
| `…/Features` | Screens and view models, one folder per area |

## License
Wavetile is free and open source under the [Mozilla Public License 2.0](LICENSE).

Not covered by that license:
- Fonts: Familjen Grotesk, Stack Sans Notch and Stack Sans Headline are under the SIL Open Font License (license files sit next to the fonts).
- Icons: [Phosphor](https://phosphoricons.com) (MIT).
- Album and podcast artwork in screenshots belongs to its owners.

Built with [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift), [GRDB](https://github.com/groue/GRDB.swift), [Nuke](https://github.com/kean/Nuke) and [Inject](https://github.com/krzysztofzablocki/Inject). Wavetile is an independent app, not affiliated with the Jellyfin project.
