# CarPlay and background audio: device pass

Written 2026-11-07 from `Features/CarPlay/CarPlayController.swift`, `App/CarPlaySceneDelegate.swift`, `Playback/AudioPlayer.swift` and the QA-2 notes in [qa-evidence.md](qa-evidence.md). This is the checklist for the early pass in [LAUNCH.md](LAUNCH.md) (next step 4) and for the CarPlay and background-audio rows of QA-6. Use a real head unit or the CarPlay simulator (I/O → External Displays → CarPlay) for everything, then repeat the starred rows (★) on a real car, because the simulator doesn't reproduce head-unit list limits, Siri or steering-wheel controls.

Record for each row: device, iOS version, build, date, pass/fail. Use a signed TestFlight build with the CarPlay entitlement (202610301302 or newer).

## 1. Launch and connection

| # | Check | Expected | Source of the check |
|---|---|---|---|
| 1 | Cold connect: force-quit the app, connect CarPlay | Tabs appear, no blank screen; app works with no phone window | Controller is created in `App.init` (`AppModel.current`); a nil model shows "Open Wavetile on your iPhone" |
| 2 | Connect while signed out | "Sign in on your iPhone" with a subtitle; signing in on the phone replaces it with the tabs without reconnecting | `rootTemplate()`, `render()` re-runs on `app.phase` |
| 3 | Connect right after a reboot, phone still locked (first unlock not yet done) | Either tabs, or "Sign in on your iPhone"; after unlocking and relaunching, tabs appear. Note whether the screen recovers on its own | Known gap: a Keychain read failure at launch looks like signed out until relaunch (QA-3) |
| 4 | Connect with podcasts off, then turn them on in Settings | Podcasts tab appears live; turning them off removes it | `signedIn?.podcasts.isEnabled` is observed |
| 5 | Sign out on the phone while connected | Screen returns to the signed-out message, no crash | `render()` on `app.phase` |
| 6 | Disconnect and reconnect mid-playback ★ | Music keeps playing on the phone speaker or route per iOS rules; reconnect shows Now Playing state correctly and lists work | `disconnect()` clears watches and the pending refresh |
| 7 | Reconnect several times in a row | No duplicated tabs, no growing memory or CPU | `connect()` re-renders; `databaseWatches` reset in `watchDatabases()` |

## 2. Browsing

| # | Check | Expected | Source of the check |
|---|---|---|---|
| 8 | Home tab | "Recently Played" and "Most Played" sections with artwork; hidden if empty; "Nothing played yet" on a new library | `homeSections` |
| 9 | Playlists tab | Names, song counts, artwork; playlists without server art show a generated cover | `loadCover` |
| 10 | Library → Albums, Artists | Lists load; an album opens Shuffle plus its songs; an artist opens Shuffle plus albums | `libraryTab`, `albumItem`, `artistItem` |
| 11 | Large library ★ | Albums and Artists lists are cut at 200 items. Confirm this is harmless, and whether the head unit enforces a smaller `CPListTemplate.maximumItemCount` and drops items or crashes | QA-2 note: fixed `listLimit = 200` |
| 12 | Template depth | Home → album → songs → Now Playing stays within the system's push limit with no failures. Try Library → Artists → artist → album → songs | `push()` |
| 13 | Artwork | Loads within a second or two on LAN and over a slow link; no placeholder stuck forever | `loadImage` via `ImageCaching` |
| 14 | Background sync while browsing | Start a library sync or play a track; the visible list refreshes about a second after writes settle without jumping or losing scroll position; progress saves don't reload artwork | `scheduleRefresh`, `changed(...)` |
| 15 | Podcasts tab (when on) | Up Next episodes with show titles; picking one plays it and opens Now Playing | `podcastSections` |

## 3. Playback

| # | Check | Expected | Source of the check |
|---|---|---|---|
| 16 | Play a song from an album | Plays from that song onward; the system Now Playing screen opens once, not stacked | `play(startAt:)`, `showNowPlaying()` guard |
| 17 | Shuffle on an album, an artist, and a playlist | Queue is shuffled; "play" order restores if shuffle is turned off on the phone | `PlaybackQueue` |
| 18 | Steering-wheel / head-unit controls ★: play/pause, next, previous, seek | Respond; Now Playing shows title, artist, artwork and elapsed time that match the phone | Remote commands in `AudioPlayer` (same data as the Lock Screen) |
| 19 | Gapless across tracks and across an album boundary | No gap or repeated audio | `AVQueuePlayer` |
| 20 | Offline, with only some songs downloaded (airplane mode) | Picking an album queues only downloaded songs; picking one with nothing downloaded stays on the list and doesn't open an empty player | `play(...)` returns `false` |
| 21 | A podcast episode that can't start (offline, dead feed) | Define the expected behavior: the Podcasts handler opens Now Playing without checking whether playback started, unlike music. Confirm there is no empty player | `podcastSections` handler |
| 22 | Switch between music and a podcast | Now Playing, remote controls and progress follow the right item | |

## 4. Audio session and interruptions (also the open `AVAudioSession` warning)

Activation runs on the main actor and errors are discarded (`try?`); the decision for 1.0 is to keep it and cover it here. Any failure in this section reopens that decision.

| # | Check | Expected |
|---|---|---|
| 23 | Navigation voice prompt over playback ★ | Music ducks or pauses and resumes by itself |
| 24 | Incoming phone call, answered and declined | Pauses; resumes only when the interruption says to |
| 25 | Siri on CarPlay ★: "Play ⟨artist or album⟩ in Wavetile", "Play music in Wavetile" | Plays and opens Now Playing; behavior without a signed-in session is graceful |
| 26 | Another audio app takes over, then Wavetile is started again | Wavetile reclaims the session and plays |
| 27 | Route changes: unplug the cable or leave the car ★, unplug headphones, connect Bluetooth | Pauses on route loss (old output unavailable), doesn't blast the phone speaker |
| 28 | Start playback with the phone locked, then lock again for 10+ minutes | Keeps playing in the background |
| 29 | AirPlay 2 to a speaker | Long-form audio routing works, controls respond |

## 5. Background audio on the phone (QA-6)

| # | Check | Expected |
|---|---|---|
| 30 | Lock Screen and Control Center controls | Play, pause, next, previous, seek, artwork and time are correct |
| 31 | Background for 30+ minutes with downloads running | No stall at track boundaries; no kill by the system |
| 32 | Low Power Mode on during playback | Playback continues; the podcast refresh BGTask may be deferred |
| 33 | Streaming a transcoded track (non-direct-play format) vs a FLAC | Both play; note any difference in start latency |
| 34 | Token expiry during playback | Skips stop after at most 10 failures in a row rather than looping the queue and hitting the server (the QA-2 fix); sign-in prompt follows |

## Notes to capture

- Head unit make/model and the maximum list item count it reported.
- Whether the Keychain-at-launch case (row 3) is reproducible after a reboot.
- Any template pushed twice, or Now Playing stacking.
- Anything that needs an engineering fix goes in [LAUNCH.md](LAUNCH.md) under QA-2 / QA-3 remaining, with the build number.
