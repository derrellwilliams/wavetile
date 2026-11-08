# Testparty — Wavetile device checks

Moved from [LAUNCH.md](LAUNCH.md) on 2026-11-07. This is the working checklist for checks you perform on a real device, covering QA-2, QA-3, QA-6 and the device portion of QA-8. Engineering prepares builds and test setups, investigates failures and implements fixes. Moving checks here does not mark them passed or waive release gates.

## Before starting

Decided Nov 7: no TestFlight upload until all eight targeted source reviews were done, so everything runs on one build. They are done; the build to test is **RC_BUILD_PLACEHOLDER** (Version 1.0.0, from commit RC_COMMIT_PLACEHOLDER, uploaded RC_DATE_PLACEHOLDER; confirm in TestFlight that processing finished). Builds 202611072010 and 202611061835 predate the review fixes and are not used. Start with the detailed CarPlay and audio pass below and the review-fix checks, then run every P0 scenario on this build.

For each check record device, iOS version, build, date, pass/fail and reproduction notes. Include head-unit/speaker details where relevant. Leave untested checks open; record any explicit deferral and rationale. Put engineering defects in LAUNCH.md with the build and a link to the failed check here.

| Check | Device / iOS | Build / date | Result | Notes |
|---|---|---|---|---|
| | | | Not run | |

## Security and review access (QA-2 / QA-3 / QA-8)

- [ ] Verify a delayed playback failure followed by a retry of the same track does not skip or pause the new attempt (R2-01); use an engineering-controlled delayed connectivity check.
- [ ] Verify audio-session changes using rows 23–29 below: interruptions, route changes, AirPlay and CarPlay. Watch for playback that never starts after interruption or starts after being paused.
- [ ] Verify AVFoundation streaming redirects with an engineering-prepared proxy: redirect an audio request to a second controlled host and confirm no Authorization header reaches it. Use test credentials only; redact credentials from evidence.
- [ ] Verify Keychain cleanup on device: sign out, relaunch and confirm the session cannot restore; exercise lock/unlock and failed-deletion retry with engineering assistance. Signed-out UI alone does not prove token deletion. Record evidence of cleanup separately from best-effort server revocation.
- [ ] From a fresh install, validate reviewer-demo login and playable content using the exact review instructions, including a blank password if applicable.
- [ ] Verify privacy-policy links open from sign-in and Settings, including a VoiceOver smoke check.

## Checks for the Nov 7 review fixes (R1–R8)

Each of these exercises a fix that automated tests cover only partly (details in [qa-evidence.md](qa-evidence.md)). Use a test account, not your main library, where a step deletes data.

- [ ] **Sign-out cleanup (R3-05, R4, R6):** with a sync running (pull to refresh) and a download in progress, sign out. Expect the sign-in screen with no alert, Lock Screen widgets back to "Nothing playing", no download Live Activity left on the Lock Screen or Dynamic Island, and no downloaded music or podcast files after signing in as a different account. Then sign in again as the first account: an empty library that syncs, nothing carried over.
- [ ] **Sign-out failure path (R3-05):** nothing to force on a device; if "Couldn't Sign Out" ever appears, record when, then close and reopen the app and sign out again.
- [ ] **Library sync with big playlists and collections (R3-01–R3-04):** against a server with a playlist over 500 songs and a collection with several albums, sync, then check song counts. Turn the server off mid-sync: expect "Library sync failed. Pull to retry.", no songs missing from playlists, and downloaded playlists still intact.
- [ ] **Kill during sync and download (section 8):** force-quit during a sync, relaunch: library intact, next refresh completes. Force-quit during a download, relaunch: it resumes; finished tracks play offline.
- [ ] **Download validity (R4-02):** point a download at a dead or paywalled link if you have one (a podcast enclosure that returns a web page works): expect a failed download, not "Downloaded".
- [ ] **Download Live Activity (R6-03):** start an album download, lock the phone, force-quit the app. Expect the activity to be gone or updated after the next launch, not frozen at old progress; tapping Download or Retry twice shows one activity.
- [ ] **Siri names (R6-02):** on a fresh install, sign in and wait for the first sync to finish, then say "Play <album name> in Wavetile" without relaunching the app. After signing out and into another account, an album from the first account is no longer recognized.
- [ ] **Widgets after sign-out (R6-04):** sign out quickly after Home loads; the Recently Played widget must be empty, and stay empty.
- [ ] **Podcast feed that breaks partway (R5-02):** follow a show whose feed has an unescaped "&" in an old episode title if you can find one; older episodes must stay, and played marks must survive a refresh.
- [ ] **Two-device podcast sync (R5-01):** follow a show on device A, check it appears on device B; unfollow on B, check A follows the change. Nothing should unfollow unless you did it.
- [ ] **Library or podcast storage failure (R8-01):** not reproducible on demand; if you ever see an empty library or podcast list after an update, note the build and time (the log entry "database didn't open" is in a sysdiagnose) and relaunch.

## Full device pass (QA-6)

Record device, iOS version, build, date and pass/fail. Check normal behavior and recovery after the interruption.

**P0 (on the RC)**
- [ ] Fresh install, upgrade with existing data, login/Quick Connect, sign-out and expired-token recovery.
- [ ] Lock Screen / Control Center controls, AirPlay, headphone unplug, calls and audio interruptions, background playback.
- [ ] Download resume/cancel, network loss mid-download, server outage, background completion.
- [ ] Airplane-mode playback of downloaded music and podcasts; reconnect recovery.
- [ ] CarPlay connection, browsing, playback and reconnect.
- [ ] VoiceOver, larger text, light/dark, first interactions after splash.

**P1**
- [ ] Widgets, deep links, download Live Activity.
- [ ] Podcasts: search, follow, stream/download, progress, chapters/transcripts, subscription sync.
- [ ] 50k-track library, Low Power Mode, low-storage handling. Record expected iOS behavior for system termination versus user force-quit.

## Detailed CarPlay and background-audio pass

Derived Nov 7 from CarPlayController, CarPlaySceneDelegate, AudioPlayer and QA evidence. The numbered rows preserve the previous CarPlay checklist references. Simulator checks can help engineering diagnose issues, but repeat starred rows (★) on a real head unit; the simulator does not reproduce head-unit limits, Siri or steering-wheel controls. All rows remain unverified until a result is recorded.

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

## 4. Audio session and interruptions

Activation now runs on a serial background queue and playback waits for it. Verify that playback resumes correctly after interruptions and that a canceled or superseded start does not play unexpectedly. This change requires a new build containing the Nov 7 fixes.

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
| 34 | Token expiry during playback | Skips stop after at most 10 failures in a row rather than looping the queue and hitting the server (the QA-2 fix). On confirmed 401, “Session expired. Sign in again” appears. Close the sign-in sheet and verify downloaded playback still works; reauthenticate as the same account and verify streaming resumes with downloads/progress intact (R1-02 fix; new build required) |

## Notes to capture

- Head unit make/model and the maximum list item count it reported.
- Whether the Keychain-at-launch case (row 3) is reproducible after a reboot.
- Any template pushed twice, or Now Playing stacking.
- Anything that needs an engineering fix goes in [LAUNCH.md](LAUNCH.md) under QA-2 / QA-3 remaining, with the build number.

## Launch-day install check

- [ ] Once the listing is live, install through the public App Store listing and confirm the app launches successfully. Record the listing URL and build.
