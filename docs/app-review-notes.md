# App Review notes (draft)

Draft written 2026-11-07 from the code and [qa-evidence.md](qa-evidence.md). Paste the block under "Notes for the reviewer" into App Store Connect → App Review Information. Fill every `⟨…⟩` before submitting; nothing here is confirmed against the final build.

## Before you paste

| Open item | Why it matters |
|---|---|
| Reviewer server URL, username and password (P0, first row in LAUNCH.md) | Review can't proceed without working credentials. Validate from a fresh install and keep the server up for the whole review |
| Whether the password is blank | Say so explicitly in the notes; App Store Connect's password field may reject an empty value |
| Final build number | Name the build the notes describe |
| Contact phone number | App Store Connect requires one in App Review Information (contact email is realslimscrawny@gmail.com) |

## Notes for the reviewer

> **What Wavetile is.** Wavetile is a music and podcast player for people who run their own Jellyfin media server (Jellyfin is free, open-source software). It has no content of its own and no accounts of its own: the user signs in to their Jellyfin server and plays the music stored there. Podcasts are optional and off by default.
>
> **Demo server (please use this to review).**
> - Server address: `⟨https://…⟩`
> - Username: `⟨…⟩`
> - Password: `⟨…⟩` ⟨or "leave the password field empty"⟩
> - The account is read-only and the library holds only royalty-free / public-domain music.
>
> **To sign in.** Launch the app → enter the server address → enter the username and password → tap Sign In. (Quick Connect, shown below the form, is an alternative that needs a second signed-in Jellyfin device, so it isn't usable for review.) The first sync takes a few seconds; Home, Music and Search fill in when it finishes.
>
> **What to try.**
> 1. Music tab → open an album → play. Playback is gapless; the Now Playing screen, Lock Screen and Control Center controls all work.
> 2. Download an album (album menu → Download). It appears under the Downloaded tab and plays in Airplane Mode.
> 3. Settings (side drawer, top left) → turn on Podcasts, then use the Podcasts tab to search the Apple podcast directory and follow a show. Podcasts are fetched from each publisher's own feed, not from the Jellyfin server.
> 4. Widgets (Now Playing, Recently Played) and a download Live Activity are available from the Home Screen / Lock Screen.
>
> **Background audio.** The app declares the `audio` background mode so music and podcasts keep playing with the screen locked or the app in the background. It also declares `fetch`, which iOS uses to check followed podcasts for new episodes (a single BGTask, `com.derrellwilliams.wavetile.podcast-refresh`).
>
> **CarPlay.** The app uses the CarPlay Audio entitlement (granted to our team on 2026-10-30). Sign in on the iPhone first; the CarPlay screen then shows Home, Playlists, Library and (if podcasts are on) Up Next, and uses the system Now Playing screen. Until the user signs in on the iPhone, CarPlay shows "Sign in on your iPhone".
>
> **Local network and HTTP.** Most Jellyfin servers run on the user's home network, so the app asks for Local Network access (`NSLocalNetworkUsageDescription`) and allows plain HTTP only to local-network hosts and to `*.ts.net` (Tailscale) names, which are encrypted by WireGuard. The app refuses to sign in to a server over HTTP anywhere else, so the access token never travels in cleartext over the internet. `NSAllowsArbitraryLoadsInMedia` is set only because some podcast publishers still serve episode audio over HTTP; it applies to media playback, not to the app's API requests.
>
> **Data.** The app has no analytics, advertising or tracking and no accounts of its own. It sends requests to the user's chosen Jellyfin server, to Apple's podcast directory (`itunes.apple.com`) when the user searches for podcasts, and to podcast publishers' hosts for feeds and audio. Privacy policy: https://wavetile.com/privacy
>
> **Purchases.** None. The app is free, with no in-app purchases or subscriptions. ⟨Confirm pricing in App Store Connect.⟩
>
> Support: https://wavetile.com/support · realslimscrawny@gmail.com

## Claims to verify before submitting

| Claim | Status | Source |
|---|---|---|
| Lossless playback | **True for streaming:** FLAC, ALAC, WAV, AIFF, MP3 and AAC direct-play up to 140 Mbps; anything else transcodes to 320 kbps MP3. **Not true of the default download:** downloads default to MP3 (~256 kbps); lossless needs Settings → Downloads → "Original (lossless when possible)". Word the listing as "plays FLAC and ALAC" or "lossless streaming", not "lossless offline", and fix the planned screenshot caption "Gapless, offline, lossless" in [search-optimization.md](search-optimization.md) | `JellyfinKit/PlaybackAPI.swift:13-28`, `Downloads/DownloadManager.swift:12-24`, `Features/Settings/SettingsDrawer.swift:87` |
| Gapless | Implemented with `AVQueuePlayer`; confirm by ear on device (not in qa-evidence.md) | `Playback/AudioPlayer.swift` |
| Podcasts optional and off by default | Settings toggle; confirm default on a fresh install | `HomeModel`, `PodcastsStore` |
| Quick Connect isn't usable for review | True if the demo server has Quick Connect disabled (the Jellyfin default is enabled but needs an already signed-in device to authorize) | `Features/Auth/QuickConnectView.swift` |
| Siri | Phrases: "Play ⟨item⟩ in/on Wavetile", "Play music in Wavetile"; mention only if the reviewer might try them | `App/MusicIntents.swift` |

## Likely reviewer questions

- **"Why does the app allow arbitrary loads?"** Answer above (podcast audio over HTTP; API traffic stays HTTPS except LAN and `ts.net`). If Apple pushes back, the fallback is dropping `NSAllowsArbitraryLoadsInMedia`, at the cost of some podcasts not playing.
- **"The app needs a server."** Covered by the demo credentials; Guideline 2.1 expects working access, so keep them live.
- **"Jellyfin" in the subtitle/description.** Nominative reference, not in the app name (see LAUNCH.md).
