---
paths:
  - "**/Features/**"
  - "**/Downloads/**"
  - "**/Persistence/**"
  - "**/Playback/**"
  - "**/DesignSystem/Components/AlbumTile.swift"
---

## Offline design
Goal: always clear what plays without a connection, and never a wrong guess across the whole library. Only certain signals change what's shown.

| Signal | Source | What it drives |
|---|---|---|
| Downloaded | The file is on the device (`DownloadsStore.available`, `downloadedTrackIDs`) | The download mark, online and off: `DownloadMark` via `downloadMarked(_:)` on tile artwork (`AlbumTile(isDownloaded:)`, the Playlists/Collections grids), the icon in `TrackRow`, VoiceOver "Downloaded" |
| No network | `NWPathMonitor` (`Connectivity.hasNetwork`) | "You're offline" `OfflineNotice`; dims what isn't downloaded (`offlineDimmed(available:)`, `PlayableRow`); disables `requiresServer()` actions; Home's Downloaded row first |
| Server unreachable | A real request failed (`ServerIdentity.observeReachability`: API responses incl. 502–504, transport errors, identity checks → `Connectivity.report`), confirmed by a probe 1 s later | "Can't reach your server" `OfflineNotice` with Retry, Home's Downloaded row, no new streams (`canStream` reads `isOnline`). **No dimming**, server actions stay enabled and say if they fail. Clears at the next answer; retries at 2 s, every 5 s for a minute, then every 30 s, and at once on a new network or foreground |

- Never dim, disable or hide on a guess about the server. The old predictive rules (grace periods, local-route and VPN detection, launch "unverified" state) were removed on 2026-11-21 after repeated bugs; don't bring them back.
- Security is separate from display: a plain-HTTP server proves its ID (`ServerIdentity`) after every path update (same-interface ones too, even while unreachable) and on foreground before the token is sent, and the player drops or holds token streams until it has (`AudioPlayer.networkChanged`, `loadOnceServerChecks`). This never changes what's shown.
- Podcasts only count a lost network: episodes stream from their feeds.
- Code: `Connectivity` (in `Features/Downloads/DownloadsStore.swift`), `Features/Downloads/Offline.swift`, `DesignSystem/Components/AlbumTile.swift` (`DownloadMark`); tests in `ConnectivityTests` and `ServerIdentityTests`.
