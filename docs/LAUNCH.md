# Wavetile release & launch plan

The single working checklist for App Store preparation, launch and follow-up. Update status here with a date and evidence; don't keep competing checklists in agent memory. An unchecked item is unfinished or unverified, not necessarily a known defect.

- Evidence behind the gates: [qa-evidence.md](qa-evidence.md) (security, privacy, Release/config, sanitizer records).
- App Store, web search and LLM discoverability notes (ASO, SEO, GEO): [search-optimization.md](search-optimization.md).
- Submission drafts (Nov 7, unreviewed): [app-review-notes.md](app-review-notes.md), [privacy-answers.md](privacy-answers.md).
- CarPlay and background-audio device pass: [carplay-device-checklist.md](carplay-device-checklist.md).

Consolidated 2026-11-06 and reorganized 2026-11-07 (tiers below, evidence and search notes split out). Historical test results are preserved, not rerun or certification of the latest build. This plan doesn't itself authorize uploads, CI setup, delegation, commits or public posts.

## Current status — 2026-11-07

| Area | State / evidence |
|---|---|
| Candidate | Version 1.0.0, build 202611061835, from `2a52299`; uploaded Nov 6, processing and external availability not verified. **Fixes since then are on `main` but in no build** (RedirectGuard, OPML bound, Keychain retry, privacy links, server-data hardening, back-chevron theme fix, audio session off the main thread), so the RC must be a new build |
| Public beta | Build 202610281900 approved for external testing; link https://testflight.apple.com/join/pk9dyfMq. That approval doesn't cover newer builds |
| Signing / CarPlay | Team, app record and App Group done. CarPlay Audio granted and enabled; signed CarPlay build 202610301302 uploaded Oct 30 (`8af183f`) |
| Automated QA | Nov 7 (Debug, iPhone 18 Pro Max, iOS 27.0): package scheme 151/151 (197 runs) and UI 17/17 with zero runtime warnings, after the QA-2/3/4 edits and a medium code review of them. Nov 5: 94/94 under ASan and TSan, none rerun on the Nov 7 edits. One earlier Nov 7 UI run failed `testWaveAndHomeTabScrollToTop` once, then passed (cause not found). Details in qa-evidence.md |
| Website / repo | Site, support/privacy pages, guides, llms.txt, JSON-LD, sitemap live; MPL-2.0 and README in place. Service/account configuration not reverified Nov 6 |
| Review access | Earlier plan: `https://demo.jellyfin.org/stable`, user `demo`, blank password. **Decision needed:** see P0 |
| Contact | realslimscrawny@gmail.com (site, support, privacy) |
| Privacy | Source review done Nov 6: policy links on sign-in and in Settings, policy wording corrected, required-reason declarations validated. Policy is local until the site is deployed; App Store privacy answers not yet entered |

**Next steps, in order**
1. Quick wins (minutes each): deploy the corrected privacy policy with the site; confirm agreements, pricing and territories in App Store Connect; verify domain transfer lock, DNSSEC and Cloudflare 2FA.
2. Decide the reviewer demo server (P0, first row).
3. ~~Run the tests on the Nov 7 QA-3/QA-2 edits~~ (done Nov 7, all passing; both warnings fixed, zero runtime warnings), then finish QA-3 and QA-2 against the table below. Both are otherwise down to the device checks.
4. Early device pass on CarPlay and background audio, since those can force large fixes. Do it on a new TestFlight build, not 202611061835: the audio-session change (activation now off the main thread) is only in `main` and is the main thing to verify (rows 23-29 of [carplay-device-checklist.md](carplay-device-checklist.md)).
5. Freeze, cut one RC build, run the full QA-6 device checklist and the P0 listing work on it.

## Before submission

Release gates. Finish each or record an explicit deferral with rationale. Original QA numbers are kept so older conversations still map. Owner "Engineering" is coding work; "User" is device, account and release decisions.

### P0 — Apple submission blockers

Nothing ships without these.

- [ ] **Reviewer access.** Use an isolated Jellyfin instance with a non-admin, read-only account and only royalty-free or public-domain music; assume the credentials will leak and keep it apart from the personal server. The public demo (`demo.jellyfin.org`) is the fallback only: it isn't ours, resets, has content we don't control, and review can take days. Validate login and playable content from a fresh install, write exact steps (including a blank password if used), and keep access up throughout review.
- [ ] **Privacy.** Deploy the policy; enter App Store privacy answers and confirm them against qa-evidence.md (QA-8). Don't assume "Data Not Collected" from the manifest alone. Check Xcode's aggregate privacy report on the final archive. Claims must match the app: "Data Not Collected" is wrong if analytics or crash reporting is added later.
- [ ] **Listing.** Finalize name, subtitle, keywords, description, categories, support URL and privacy URL (draft copy in [search-optimization.md](search-optimization.md#app-store-aso)).
- [ ] **Screenshots** in required sizes from the demo library (licensed/public-domain music and artwork; keep source and license notes). Strip real server addresses, usernames and tokens from every capture and video.
- [ ] **Compliance.** Age-rating questionnaire, content rights, export compliance.
- [ ] **Commercial.** Pricing, territories, applicable agreements and account information, release timing.
- [ ] **Review notes** explain the Jellyfin requirement, optional podcasts, background audio and CarPlay. Verify feature claims (such as lossless playback) against actual settings. Note that "Jellyfin" appears in the subtitle and description as a nominative reference, not in the app name.
- [ ] **RC (Engineering + User).** Record final commit and build, run relevant automated regressions and the device checklist, confirm TestFlight processing. An uploaded build isn't a tested or approved one.
- [ ] **Submit** the tested build, resolve warnings, and record submission date, build and review outcome here.

Apple references: [submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [review access](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/), [privacy](https://developer.apple.com/app-store/app-privacy-details/), [review guidelines](https://developer.apple.com/app-store/review/guidelines/). Recheck current requirements when filling the submission.

### P1 — Quality gates

Project goals, not Apple requirements. Each has a "done when" so it can't run forever; anything beyond it is recorded as accepted residual risk.

| ID | Status | Owner | Done when |
|---|---|---|---|
| QA-3 | Partial, Nov 7 | Engineering + User | Security review. Fixed: API/OPML bounds, Keychain retry, background-download redirect containment, policy wording. Open items under "QA-2 / QA-3 remaining" below. Further resource-exhaustion testing is accepted residual risk |
| QA-2 | Partial, Nov 7 | Engineering | Code review of Playback, Downloads, Persistence/Sync, Podcasts, JellyfinKit and CarPlay. Fixed: an endless skip loop, unbounded server-sync decoding, an empty-feed prune (details in qa-evidence.md). Open items under "QA-2 / QA-3 remaining" below. A second-opinion review (was QA-10) is optional |
| QA-8 | Partial | Engineering + User | Remaining items are P0 (policy deploy, privacy answers, reviewer access) plus runtime background audio and CarPlay checks from QA-6. Privacy slice Nov 6 and Release/config slice Nov 7 are done |
| QA-6 | Open | User + Engineering | P0 device scenarios below pass on the RC; failures investigated |
| QA-4 | Done Nov 7 | Engineering | Database migration tests and unusual-server-data tests added and passing: 28 new tests, full package scheme 150/150 (196 runs), UI 17/17 (qa-evidence.md). They also led to fixes for blank names, bad durations and a sort-key edge case. Download manager/engine and AudioPlayer engine tests are P2 |
| QA-5 | Open | Engineering | Xcode Analyze triaged and results recorded (the compiler warnings from the Release build included) |
| QA-7 | Ongoing | User | Organizer/TestFlight crash reports inspected during beta and before submission; record build, period and unresolved crashes |
| QA-1 | Done Nov 5 | Engineering | Sanitizer runs complete. Retest affected paths after later fixes |

### QA-2 / QA-3 remaining

- [x] **Engineering:** run the package and UI tests on the Nov 7 edits. Done Nov 7: package 150/150, UI 17/17 (Claude can run `xcodebuild` as a plain command; see qa-evidence.md).
- [x] **Engineering:** `Environment<Theme/Bool>` warning fixed Nov 7. The cause was the back-chevron renderer reading a bare `TintedBarIcon`'s environment (it also used the default theme); UI run now shows zero runtime warnings.
- [ ] **User:** the `AVAudioSession` main-thread warning is fixed in code (activation moved to a serial background queue, play waits for it); verify interruptions, route changes, AirPlay and CarPlay on device (QA-6, rows 23-29 of the CarPlay checklist).
- [x] **Engineering:** note the CarPlay review items for the device pass (QA-6). Done Nov 7 in [carplay-device-checklist.md](carplay-device-checklist.md); the pass itself is a User task.
- [ ] **User:** verify AVFoundation streaming redirects with a redirecting proxy.
- [ ] **User:** verify Keychain cleanup on device.
- [ ] **Engineering:** recheck dependency advisories on the final archive.

### Real-device checklist (QA-6)

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

- [ ] Confirm the public listing and install path work; record the App Store ID/URL.
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
