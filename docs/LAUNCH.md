# Wavetile release & launch plan

The working checklist for engineering, App Store preparation, launch and follow-up. User device checks were signed off by the tester on 2026-11-08 (build 202611072135, bulk sign-off). Update status here with a date and evidence; don't keep competing checklists in agent memory. An unchecked item is unfinished or unverified, not necessarily a known defect.

- Evidence behind the gates: [qa-evidence.md](qa-evidence.md) (security, privacy, Release/config, sanitizer records).
- App Store, web search and LLM discoverability notes (ASO, SEO, GEO): [search-optimization.md](search-optimization.md).
- Submission copy reviewed Nov 7: [app-store-listing.md](app-store-listing.md), [app-review-notes.md](app-review-notes.md), [privacy-answers.md](privacy-answers.md). Account entry done Nov 8 except the build; final-build sign-off remains open.
- Reviewer server preparation (not used; public demo chosen Nov 8): [reviewer-server.md](reviewer-server.md).
- User device checks and results: signed off by the tester 2026-11-08 on build 202611072135 (QA-2/QA-3 device verification, QA-6, reviewer access and CarPlay/audio).

Consolidated 2026-11-06 and reorganized 2026-11-07 (tiers below, evidence and search notes split out). Historical test results are preserved, not rerun or certification of the latest build. This plan doesn't itself authorize uploads, CI setup, delegation, commits or public posts.

## Current status — 2026-11-10

| Area | State / evidence |
|---|---|
| Unreleased on `main` | Nothing: `main` (`8f83647`) is what build 202611110730 was cut from. The token risk on plain-HTTP servers is accepted (see QA-2 / QA-3 remaining) |
| Latest upload | Version 1.0.0, build 202611110730 from `8f83647` (main), uploaded Nov 11 07:32 (Mac local time); export succeeded and App Store Connect reported it processing. Adds to 202611101951 the Nov 11 false-offline fix (`Connectivity`: a first miss after foreground or same-interface chatter retries in 1 s before "Can't reach your server" shows; the retry chain no longer ends on a voided check; retries back off 1/2/4/8 s then 15 s; same-interface updates bring the next retry forward while unreachable). Device check: background the app a few minutes, reopen at home on Wi-Fi; the notice should not show or should clear within seconds. Not yet device-checked. Previous upload: build 202611101951 from `f04b3ec` (main), Nov 10 19:53, which added to 202611090945: the Nov 10 streaming-stall fixes (same-network path updates keep the playing stream, 120 s buffer, 30 s on metered paths), the Undo banner and collection-removal changes, Now Playing podcast links, and the tab-tap change (tapping the current tab: back to root, then scroll to top when scrolled down, then refresh at the top, one step per tap; Search and Downloads only scroll). None are device-checked yet, and the tab-tap behavior has not been run on the simulator. Not yet confirmed in TestFlight; not attached to the version. Previous upload: build 202611090945 from `b4472e2`, Nov 9 09:48 MST |
| Candidate | Version 1.0.0, build 202611072135 from `34c899f` (all review 1–8 fixes), uploaded Nov 7 21:38 PT; App Store Connect reported the upload processing, and TestFlight availability is not yet verified. Builds 202611072010 and 202611061835 predate the review fixes and are not used for device checks. Device sign-off done Nov 8 (tester, bulk). This build is not the final RC; none is attached to the version yet |
| Public beta | Build 202610281900 approved for external testing; link https://testflight.apple.com/join/pk9dyfMq. That approval doesn't cover newer builds |
| Signing / CarPlay | Team, app record and App Group done. CarPlay Audio granted and enabled; signed CarPlay build 202610301302 uploaded Oct 30 (`8af183f`) |
| Automated QA | Nov 8 rerun at `99a1cf7` (Debug, iPhone 18 Pro Max, iOS 27.0): package scheme 178/178 (246 runs), zero runtime warnings; UI 16/17 on the full run, the one failure (`testNowPlayingAudit`, contrast on the remaining-time label) passed on rerun, so intermittent and not reproduced. Second unexplained one-off UI failure (Nov 7: `testWaveAndHomeTabScrollToTop`), so UI is "passes on rerun", not clean. Nov 5: 94/94 under ASan and TSan, none rerun on the Nov 7–8 edits. Details in qa-evidence.md |
| Website / repo | Site, support/privacy pages, guides, llms.txt, JSON-LD, sitemap live; MPL-2.0 and README in place. Service/account configuration not reverified Nov 6 |
| Review access | Earlier plan: `https://demo.jellyfin.org/stable`, user `demo`, blank password. **Decided Nov 8: use the public demo** (user choice, accepting the risks in P0). Checked Nov 8: server up (v12.4.0), `demo` login with blank password works, library has 5 songs / 4 albums / 3 artists. Rechecked Nov 10: still v12.4.0, `demo` blank-password login works, 5 songs / 4 albums / 4 artists |
| Contact | realslimscrawny@gmail.com (site, support, privacy) |
| Privacy | Source review done Nov 6: policy links on sign-in and in Settings, policy wording corrected, required-reason declarations validated. Live policy verified Nov 7: main content matches the corrected local policy. Nov 8: answers entered and published in App Store Connect (Data Not Collected). Final archive privacy report remains open |
| App Store Connect | Nov 8, entered or saved: agreements and EU DSA, Free price and all territories, App Information (subtitle, categories, age rating, content rights), privacy, listing text and keywords, 7 screenshots (to trim), App Review Information and notes. Not done: build attachment, release type, final screenshot trim, Submit |
| Cloudflare | Nov 8: tester reported transfer lock, DNSSEC and 2FA enabled (per-item status not recorded) |

**Next steps, in order**
1. Quick wins: done Nov 8 (agreements, Free price and territories in App Store Connect; Cloudflare transfer lock, DNSSEC and 2FA reported enabled).
2. Reviewer access: done Nov 8. Public Jellyfin demo chosen and review notes entered ([app-review-notes.md](app-review-notes.md)). Recheck the demo just before submitting. A dedicated server ([reviewer-server.md](reviewer-server.md)) stays an option.
3. Current pins rechecked Nov 7 and again Nov 10 (all 10 in `Package.resolved`, including swift-nio 2.105.0) with no matching OSV advisories; repeat against the final archive to finish the remaining QA-2/QA-3 engineering check. Nov 8 package regressions pass (178/178) and UI passes on rerun (one intermittent audit failure; see Automated QA).
4. Confirm build 202611072135 finishes processing and becomes available in TestFlight, then device-check it, once, on that single build (done 2026-11-08, tester sign-off); investigate any reported failures. If a fix lands, it needs a new build and a rerun of the affected checks. Build 202611072010 is not being used for it.
5. Targeted source reviews 1–8 are done (findings fixed or deferred in qa-evidence.md); what remains is the optional items (device verification was signed off 2026-11-08) listed under each section.
6. Listing, privacy, compliance and review fields are entered (Nov 8). Remaining: freeze, cut one RC build (rerun package and UI tests first), generate the archive privacy report, recheck dependency advisories on it, upload and attach it, trim the screenshots, choose the release type, recheck the demo server, then Add for Review.

## Before submission

Release gates. Finish each or record an explicit deferral with rationale. Original QA numbers are kept so older conversations still map. Owner "Engineering" is coding work; "User" here is account and release decisions. Device execution was signed off by the tester on 2026-11-08.

### P0 — Apple submission blockers

Nothing ships without these.

- [ ] **Reviewer access.** Nov 8: decided to use the public demo with `demo` and a blank password (entered in App Review Information); recheck it just before submitting. Original plan: use an isolated Jellyfin instance with a non-admin, read-only account and only royalty-free or public-domain music; assume the credentials will leak and keep it apart from the personal server. The public demo (`demo.jellyfin.org`) is the fallback only: it isn't ours, resets, has content we don't control, and review can take days. Write exact steps (including a blank password if used), collect reviewer-access results from the device pass, and keep access up throughout review.
- [ ] **Privacy.** Nov 8: entered and published in App Store Connect (Data Not Collected, policy URL `https://wavetile.com/privacy`, no choices URL); still to do: Xcode privacy report on the final archive. Live corrected policy verified Nov 7; enter the reviewed App Store privacy answers and confirm them against qa-evidence.md (QA-8). Don't assume "Data Not Collected" from the manifest alone. Check Xcode's aggregate privacy report on the final archive. Claims must match the app: "Data Not Collected" is wrong if analytics or crash reporting is added later.
- [ ] **Listing.** Copy and URLs prepared/reviewed Nov 7 in [app-store-listing.md](app-store-listing.md). Nov 8: entered in App Store Connect (name, subtitle, categories, promotional text, description, keywords, URLs). Still to do: confirm final-build claims; no build attached yet (icon shows a placeholder until the RC is attached).
- [ ] **Screenshots** in required sizes from the demo library (licensed/public-domain music and artwork; keep source and license notes). Strip real server addresses, usernames and tokens from every capture and video. Nov 8: instead of the demo library, captured from the user's own library in the Simulator (iPhone 18 Pro Max, 1320×2868, downscaled to 1206×2622 for the 6.3" slot, which rejects 1320×2868); 7 uploaded to App Store Connect, to be trimmed to about 5. These show real third-party album art and artists, so the rights risk of guideline 5.2 is accepted by the user.
- [ ] **Compliance.** Age-rating questionnaire done Nov 8 (13+ in 172 countries, 12+ Vietnam and Korea, 14+ Brazil; social media, user-generated content and age assurance answered No). Content rights set to Yes (third-party content, rights held) Nov 8; export compliance needs nothing now (`ITSAppUsesNonExemptEncryption=false`; confirm in the final archive). App Information also entered Nov 8: subtitle, categories Music + Entertainment (Entertainment means no sales in Afghanistan).
- [ ] **Commercial.** Pricing, territories, applicable agreements and account information, release timing. Nov 8: app will be free. Free Apps Agreement active (updated license accepted) and EU DSA compliance completed in App Store Connect; Paid Apps Agreement intentionally left unsigned. Price set to Free and all territories selected under Pricing and Availability (Nov 8). Still to do: release timing.
- [ ] **Review notes** reviewed Nov 7 in [app-review-notes.md](app-review-notes.md); Nov 8: entered and saved in App Store Connect (sign-in `demo` with blank password, contact details, notes block); the final build is still to attach. Notes explain the Jellyfin requirement, optional podcasts, background audio and CarPlay. Verify feature claims (such as lossless playback) against actual settings. Note that "Jellyfin" appears in the subtitle and description as a nominative reference, not in the app name.
- [ ] **Rejection-risk review (2026-11-11).** Ranked by likelihood; work these before Add for Review.
  - [ ] **High: reviewer access on the public demo** (not ours; resets, 5 songs, may change or go down during review; a sign-in failure is a 2.1 rejection). Mitigation: recheck right before submitting, or stand up the dedicated server in [reviewer-server.md](reviewer-server.md) (user hosts it); the notes now ask the reviewer to reply if the demo is down.
  - [ ] **Medium: unverified RC.** Build 202611110730 isn't device-checked; a false "offline" notice or stream stall during review reads as a broken app (2.1). Device-check it, then freeze it as the RC.
  - [ ] **Medium: screenshots** show real third-party art and artists and may show server names or usernames (5.2, 2.3). Trim to about 5 and strip identifiers, or recapture from a demo library.
  - [x] **Low–medium: cleartext HTTP, background modes, CarPlay, Live Activities.** Explained in [app-review-notes.md](app-review-notes.md) (Nov 11); paste the updated block into App Store Connect. HTTPS (e.g. a Cloudflare tunnel) would remove the HTTP question and the accepted token risk.
  - [x] **Low–medium: "Jellyfin" in the subtitle.** The listing already carries "independent app, not affiliated with the Jellyfin project" ([app-store-listing.md](app-store-listing.md)); keep Jellyfin out of the name and icon.
  - [ ] **Low–medium: privacy label.** "Data Not Collected" holds only if the final archive's privacy report matches; Apple podcast search/chart requests and recommendation titles and genre IDs are listed in [privacy-answers.md](privacy-answers.md). Generate the report (archive asks approval).
  - [ ] **Low: podcast content and age rating.** Recheck the rating answers against arbitrary publisher feeds.
- [ ] **RC (Engineering + User).** Record final commit and build, run relevant automated regressions, collect required device results, and confirm TestFlight processing. An uploaded build isn't a tested or approved one.
- [ ] **Submit** the tested build, resolve warnings, and record submission date, build and review outcome here.

Apple references: [submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [review access](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/), [privacy](https://developer.apple.com/app-store/app-privacy-details/), [review guidelines](https://developer.apple.com/app-store/review/guidelines/). Recheck current requirements when filling the submission.

### P1 — Quality gates

Project goals, not Apple requirements. Each has a "done when" so it can't run forever; anything beyond it is recorded as accepted residual risk.

| ID | Status | Owner | Done when |
|---|---|---|---|
| QA-3 | Partial, Nov 7 | Engineering | Security review. Fixed: API/OPML bounds, Keychain retry, background-download redirect containment, policy wording. Engineering follow-up below; device sign-off done 2026-11-08 (tester). Further resource-exhaustion testing is accepted residual risk |
| QA-2 | Partial, Nov 7 | Engineering | Code review of Playback, Downloads, Persistence/Sync, Podcasts, JellyfinKit and CarPlay. Fixed: an endless skip loop, unbounded server-sync decoding, an empty-feed prune (details in qa-evidence.md). Engineering follow-up below; device sign-off done 2026-11-08 (tester). A second-opinion review (was QA-10) is optional |
| QA-8 | Partial | Engineering + User | Remaining items are P0 (privacy answers, reviewer access, final archive privacy report) and the device sign-off (done 2026-11-08). Corrected live policy verified Nov 7. Privacy slice Nov 6 and Release/config slice Nov 7 are done |
| QA-6 | Signed off 2026-11-08 (tester) | Engineering support | Device checks signed off in bulk on build 202611072135; investigate any later reported failures |
| QA-4 | Done Nov 7 | Engineering | Database migration tests and unusual-server-data tests added and passing: 28 new tests, full package scheme 150/150 (196 runs), UI 17/17 (qa-evidence.md). They also led to fixes for blank names, bad durations and a sort-key edge case. Download manager/engine and AudioPlayer engine tests are P2 |
| QA-5 | Done Nov 7 | Engineering | Release simulator Analyze passed at `4060f29`: 0 analyzer findings/errors, 11 compiler warnings triaged with dispositions in qa-evidence.md. Warnings remain; no release blocker established |
| QA-7 | Ongoing | User | Organizer/TestFlight crash reports inspected during beta and before submission; record build, period and unresolved crashes |
| QA-1 | Done Nov 5 | Engineering | Sanitizer runs complete. Retest affected paths after later fixes |

### QA-2 / QA-3 remaining

- **Accepted residual risk (user, 2026-11-10): token on plain-HTTP servers after a same-subnet Wi-Fi hop.** Same-interface path updates no longer drop the playing stream; it keeps its open connection while the server is re-verified (about 0.5 s plus one probe). If the listener hopped from home Wi-Fi to another network using the same address range, and someone there runs a look-alike server at the old address, that server could receive the Jellyfin session token (a revocable session, not the password) in that window. Done when: not planned; serving Jellyfin over HTTPS removes it. Code: `Connectivity.pathChanged`, `AudioPlayer.networkChanged(strict:)`.

- [x] **Engineering:** run the package and UI tests on the Nov 7 edits. Done Nov 7: package 150/150, UI 17/17 (Claude can run `xcodebuild` as a plain command; see qa-evidence.md).
- [x] **Engineering:** `Environment<Theme/Bool>` warning fixed Nov 7. The cause was the back-chevron renderer reading a bare `TintedBarIcon`'s environment (it also used the default theme); UI run now shows zero runtime warnings.
- [x] **Engineering:** note the CarPlay review items for the device pass (QA-6). Done Nov 7; device pass signed off 2026-11-08.
- [x] **Engineering:** Nov 7 current-pin advisory recheck: 20 OSV queries returned no matches; recent upstream NIO fix thresholds checked. Details and coverage limits in qa-evidence.md.
- [ ] **Engineering:** recheck dependency advisories and the actual dependency inventory on the final archive.

### Targeted pre-release reviews — added November 7, 2026

As of Nov 7, the initial source reviews and fixes for all eight source reviews and their fixes are complete. Sections 1–8 still require device verification before they can close (UI tests were rerun Nov 7 and pass); section 3's stubbed-server sync tests with seeded downloads were added Nov 8 (6 tests, passing). This extends QA-2/QA-3; earlier reviews remain historical evidence, not completion of this pass. Track findings and verification in [qa-evidence.md](qa-evidence.md); real-device execution was signed off 2026-11-08.

| Order | Scope | Status |
|---|---|---|
| 1 | Authentication/networking: credentials, redirects, transport, restore, logout and server switching | Initial source review and R1-01/R1-02 fixes Nov 7; device evidence outstanding |
| 2 | Playback/queue: concurrency, transitions, interruptions, background operation and restoration | Initial source review and R2-01/R2-02 fixes Nov 7; device evidence outstanding |
| 3 | Persistence/library sync: migrations, partial sync, stale records and account isolation | Source review and R3-01–R3-05 fixes Nov 7 (package 161/161); stubbed-server sync tests with seeded downloads added Nov 8 (6 tests, passing), UI rerun done Nov 8; account-ID filename limitation goes to section 8 |
| 4 | Downloads/offline: interruption, missing files, cleanup and fallback | Source review and R4-01–R4-03 fixes Nov 7 (package 163/163); deferrals recorded in qa-evidence.md; device checks outstanding |
| 5 | Podcasts: malformed feeds, subscription sync, progress and external URLs | Source review and R5-01–R5-05 fixes Nov 7 (package 173/173); deferrals recorded in qa-evidence.md; device checks outstanding |
| 6 | System integrations: CarPlay, Siri, widgets, Live Activities and shared state | Source review and R6-01–R6-05 fixes Nov 7 (package 175/175, app target builds); deferrals recorded in qa-evidence.md; device checks outstanding |
| 7 | Screens/release configuration: errors, accessibility, navigation, debug behavior and entitlements | Source review Nov 7: no defects in configuration, debug flags, entitlements or error surfaces; UI audit 17/17; device accessibility and navigation checks outstanding |
| 8 | Cross-subsystem scenarios: server switch during download, network loss during playback, termination during sync and upgrade with existing data | Traced Nov 7; R8-01 fixed (stand-in database could delete finished downloads); kill-mid-sync/sign-out and upgrade device checks outstanding |

Each pass traces user flows through dependencies and records findings with source locations, severity, impact and reproduction/verification steps. Fix release blockers and add meaningful regression coverage; record optional refactors separately. A pass closes only when findings are fixed and verified or explicitly deferred with rationale. Source review does not replace device sign-off.

- [x] **R1-01 (high):** blocked cross-origin redirects when the original or destination URL contains credential query parameters/userinfo; regression coverage added Nov 7. See qa-evidence.md.
- [x] **R1-02 (medium):** added a persistent reauthentication action on authenticated API 401s, media-failure credential checks, and in-place credential replacement for the same account. Automated recovery/data-preservation coverage added Nov 7; final-device interaction check signed off 2026-11-08.
- [x] **R2-01 (high):** delayed failure recovery now checks the current player item and playback intent generation. Device verification remains open; see qa-evidence.md.
- [x] **R2-02 (medium):** preserve Up Next reordering across shuffle toggles, including edits while shuffled. See qa-evidence.md.
- [x] **R3-01–R3-05 (high/medium):** incomplete or unvalidated library reads no longer replace, prune or delete cached data or server collections; incomplete sync fails before `lastCompleted`; sign-out cancels sync and closes the database before deleting it (a close failure keeps the session and shows an alert). Details in qa-evidence.md. UI rerun after the Settings alert and stubbed-server sync tests with seeded downloads done Nov 8.
- [x] **R4-01–R4-03 (high/medium/low):** a failed database read no longer removes a download; empty or non-audio responses are failed instead of saved as done; finished downloads whose file is gone are queued again. Deferrals (orphan-file sweep, disk-full check, duplicate Live Activity and others) are listed in qa-evidence.md.
- [x] **R5-01–R5-05 (high/medium/low):** a damaged Jellyfin copy of the subscription list no longer unfollows every show; a feed that breaks partway no longer prunes episodes or renames the show; non-audio episode downloads fail instead of saving; removed or missing episode download files are cleaned up or queued again. Deferrals (sync clock skew, GUID-less episodes, sub-30-second episodes and others) are listed in qa-evidence.md.
- [x] **R6-01–R6-05 (high/medium/low):** sign-out now stops and closes the podcast database before deleting it; Siri's vocabulary updates after syncs and sign-in/out; download Live Activities are ended at sign-out and orphaned ones cleaned up at launch (one per collection); widgets can't be repopulated after sign-out; an odd album ID can't crash the widget. Deferrals (Lock Screen access by design, CarPlay offline feedback and refresh under steady writes) are in qa-evidence.md.
- [x] **R8-01 (medium):** when a library or podcast database can't open, the temporary stand-in no longer gets download managers, so finished background downloads aren't deleted against it; the fallback is logged. Sections 7 and 8 otherwise produced no defects; deferrals (account-ID file names for cloned servers, silent fallback banner, interrupted sign-out order, manual refresh killed mid-sync) are in qa-evidence.md.
- [ ] Before closing section 1, complete the media-redirect, Keychain and reauthentication device checks (signed off 2026-11-08). Review server-switch cancellation and data isolation in sections 3, 4 and 8.
- [ ] Before closing section 2, complete the delayed failure/retry and playback, interruption, routing and CarPlay device checks (signed off 2026-11-08). Decide whether revisiting previously played tracks on shuffle and queue restoration after relaunch meet the intended release behavior (see qa-evidence.md).

### P2 — Deferred (explicit)

- QA-9: GitHub Actions package-test CI. Revisit after first submission.
- SwiftLint rule set (the Analyze half of QA-5 stays in P1).
- Download manager/engine and AudioPlayer engine tests (migration tests stay in QA-4).
- Offline-play reporting to Jellyfin, incremental library sync, multi-account support, collection rename (see the backlog in qa-evidence.md).

## Launch preparation — can run alongside QA

Supports a good launch; none of it blocks App Review.

- [x] Domain bought, auto-renew on; site live with Home, guides, Privacy, Support, llms.txt, JSON-LD, sitemap (Oct 29).
- [x] AI crawlers allowed in robots.txt; Cloudflare DNS only (Oct 29).
- [x] Public beta link enabled and linked on site (Oct 29).
- [x] GitHub homepage/topics, MPL-2.0 license, user-facing README (Oct 29).
- [ ] Domain hardening: transfer lock, DNSSEC, Cloudflare 2FA (User; quick win above).
- [ ] Verify Google Search Console and Bing Webmaster Tools; submit the sitemap.

## Launch day — after the App Store listing is live

- [ ] Confirm the public listing is live; record the App Store ID/URL and record the install result.
- [ ] Replace site beta/coming-soon calls to action with the App Store badge/link; keep beta access only where intentional.
- [ ] Enable the `apple-itunes-app` Smart App Banner in `site/index.html`; replace the `.qr` placeholder with an SVG QR code for the listing.
- [ ] Add `downloadUrl` and an `offers` object to MobileApplication JSON-LD, matching actual price/currency. Add ratings only once real reviews exist.
- [ ] Update site guides, llms.txt, README and GitHub links; update sitemap `lastmod` for changed pages.
- [ ] Publish release notes/changelog.
- [ ] Check the support inbox and crash reports after release.

## After launch

- [ ] Monitor crashes, reviews and support; prioritize a maintenance update from real findings.
- [ ] Add an in-app rating prompt at a good moment (never first launch); reply to every review.
- [ ] Trademark search (USPTO classes 9, 41) and consider filing (User; planning item, not an Apple requirement).
- [ ] Monthly (GEO): ask ChatGPT, Claude, Perplexity and Gemini "best Jellyfin music app for iPhone" and log the results.
