# Wavetile release, launch & growth plan

This is the single working checklist for App Store preparation, launch and follow-up. Update status here, with a date and evidence; do not maintain competing checklists in agent memory. An unchecked item is unfinished or unverified, not necessarily a known defect.

Consolidated 2026-11-06 from `docs/LAUNCH.md`, project-memory `pre-submission-qa.md` (updated 2026-11-05), `app-store-readiness.md` (initially 2026-10-24, later CarPlay update), and `site/README.md`. The memory files remain historical sources; this document supersedes their next-step instructions. Historical test results below are preserved, not newly rerun or certification of the latest build.

## Current status — 2026-11-06

| Area | State / evidence |
|---|---|
| Candidate | Version 1.0.0, build 202611061835, from commit `2a52299`; archive and TestFlight upload succeeded November 6 (includes shortened download quality label). Xcode reported uploaded package processing; processing completion and external availability not verified |
| Public beta | Build 202610281900 previously approved for external testing; public link https://testflight.apple.com/join/pk9dyfMq. Approval of that build does not establish approval of the latest one |
| Signing / CarPlay | Developer team, app record and App Group setup completed sufficiently for uploads. CarPlay Audio granted and enabled on App ID; signed CarPlay build 202610301302 uploaded October 30 (`8af183f`) |
| Automated QA | November 5: 94/94 package tests under ASan and TSan, no reports; final plain UI run 17/17. See evidence below |
| Website / repo | Site, support/privacy pages, guides, llms.txt, JSON-LD and sitemap in place; MPL-2.0 license and user-facing README. Live service/account configuration not reverified November 6 |
| Review access | Previously used `https://demo.jellyfin.org/stable`, username `demo`, blank password. Revalidate before submission; use an isolated read-only demo server if unreliable |
| Contact | realslimscrawny@gmail.com (site, support and privacy) |
| Privacy readiness | QA-8 privacy source review completed November 6: policy links on sign-in and in Settings, corrected policy wording, existing required-reason declarations validated. Release simulator build and packaged-manifest checks passed. App link changes require a future TestFlight build; website deployment and final App Store privacy answers still need verification |
| Immediate next step | Finish the remaining QA-8 checks (reviewer access, background audio, CarPlay, final archive/privacy answers), then security review (QA-3) and area reviews (QA-2). Device testing can run alongside these |

## Before submission

These are our release gates. Finish them or record an explicit deferral and rationale; distinguish project quality goals from Apple's submission requirements. Original QA numbers are retained so older conversations still map to this list. Owner “Engineering” means the coding work; “User” means device/account or release decisions. This plan does not itself authorize uploads, CI setup, delegation, commits or public posts.

### Engineering and review readiness

| ID | Status | Owner | Work / completion evidence |
|---|---|---|---|
| QA-1 | Done Nov 5 | Engineering | Sanitizer investigation and runs; detailed historical results below. Retest affected paths after subsequent fixes |
| QA-8 | Partial — privacy source review done Nov 6 | Engineering + User | Privacy links added before sign-in and in Settings; policy corrected; required-reason declarations checked. See privacy evidence below. Remaining: deploy policy, confirm App Store privacy answers and final archive report; background audio, reviewer access, CarPlay and broader Release-debug checks remain open |
| QA-3 | Open | Engineering | Security review: access tokens and Keychain, cleartext rules and redirects, media ATS exception, feed/OPML parsing. Resolve findings and document residual risks |
| QA-2 | Open | Engineering | Review Playback, Downloads, Persistence/Sync, Podcasts, JellyfinKit and CarPlay. Investigate recorded runtime warnings: AVAudioSession activated on main thread; Environment<Theme/Bool> accessed outside a View |
| QA-4 | Open | Engineering | Add meaningful tests for download resume/cancel/low disk, database migrations and unusual server data. Existing bookkeeping tests do not establish manager/engine coverage; AudioPlayer engine coverage remains a gap to assess |
| QA-5 | Open | Engineering | Xcode Analyze and a small SwiftLint rule set; triage findings and record results |
| QA-6 | Open | User + Engineering | Complete real-device checklist below; Engineering investigates failures |
| QA-7 | Ongoing | User | Inspect Organizer/TestFlight crash reports during beta and before submission; record build, period checked and any unresolved crashes |
| QA-9 | Proposed | Engineering + User | GitHub Actions package-test CI, pending user approval; explicitly defer if not needed for first submission |
| QA-10 | Open | User + Engineering | Planned second-opinion review from another provider; choose provider/model when requested, record findings and disposition |
| RC | Open | Engineering + User | After fixes, record final commit/build, run relevant automated regressions and device smoke tests, and confirm TestFlight processing. Do not equate an uploaded build with a tested/approved release |

### Real-device checklist (QA-6)

Record device, iOS version, build, date and pass/fail for each scenario. Check normal behavior and recovery after the interruption.

- [ ] Fresh install, upgrade with existing data, login/Quick Connect, sign-out and expired-token recovery.
- [ ] Lock Screen / Control Center controls, AirPlay, headphone unplug, calls/audio interruptions and background playback.
- [ ] Download resume/cancel, network loss mid-download, server outage and background completion. Record expected iOS behavior separately for system termination versus user force-quit.
- [ ] Airplane-mode playback of downloaded music and podcasts; unavailable content and reconnect recovery.
- [ ] 50k-track library, Low Power Mode and low-storage handling.
- [ ] Widgets, deep links and download Live Activity.
- [ ] CarPlay connection, browsing, playback and reconnect.
- [ ] Podcasts: search, follow, stream/download, progress, chapters/transcripts and subscription sync.
- [ ] VoiceOver, larger text, light/dark appearance and first interactions after splash.

### Store listing and reviewer package

- [ ] Revalidate review login and playable content from a fresh install; write exact login steps (including blank password if using the public demo). Keep review access available throughout review.
- [ ] Prepare licensed/public-domain demo music and artwork; retain source/license notes. Remove real server addresses, usernames and tokens from captures.
- [ ] Capture current UI for site and App Store in required sizes. Sequence/copy: see [App Store (ASO)](#app-store-aso).
- [ ] Finalize name, subtitle, keywords, description, categories, support URL and privacy URL in App Store Connect.
- [ ] Complete age-rating questionnaire, privacy answers, content-rights and export-compliance information. Confirm privacy claims against QA-8; do not assume “Data Not Collected” solely from the manifest.
- [ ] Confirm pricing, territories, applicable agreements/account information and release timing.
- [ ] Review notes explain Jellyfin requirement, optional podcasts, background audio and CarPlay; verify feature claims such as lossless playback against actual settings.
- [ ] Select the tested final build, resolve submission warnings and submit when requested. Record submission date/build and review outcome here.

Apple references: [submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [review access](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/), [privacy](https://developer.apple.com/app-store/app-privacy-details/), [review guidelines](https://developer.apple.com/app-store/review/guidelines/). Recheck current requirements when filling the submission.

## Launch preparation — can run alongside QA

These support a good launch; marketing work does not block App Review.

- [x] Domain bought, auto-renew recorded on; site live with Home, guides, Privacy, Support, llms.txt, JSON-LD and sitemap (Oct 29 record).
- [x] AI crawlers allowed in robots.txt; Cloudflare recorded as DNS only (Oct 29).
- [x] Public beta link enabled and linked on site (Oct 29).
- [x] GitHub homepage/topics, MPL-2.0 license and user-facing README ready (Oct 29).
- [ ] Domain hardening: verify transfer lock, DNSSEC and Cloudflare 2FA (User).
- [ ] Trademark search (USPTO classes 9, 41); consider filing (User; retained planning item, not asserted Apple requirement).
- [ ] Verify Google Search Console and Bing Webmaster Tools; submit sitemap.
- [ ] Draft launch posts and prepare press kit: icon, licensed screenshots, 30-second video, description and contact.
- [ ] Recruit beta testers / submit awesome-jellyfin listing when requested. Keep jellyfin.org for after launch and eligibility.
- [ ] Local deployment-account cleanup: `vercel logout` when deploys are done (User).

## Launch day — after the App Store listing is live

- [ ] Confirm the public listing and install path work; record the App Store ID/URL.
- [ ] Replace site beta/coming-soon calls to action with the App Store badge/link as appropriate; retain beta access only where intentional.
- [ ] Enable `apple-itunes-app` Smart App Banner in `site/index.html`; replace the `.qr` placeholder with an SVG QR code for the listing.
- [ ] Add `downloadUrl` and an `offers` object to MobileApplication JSON-LD, matching actual price/currency. Add ratings only once real reviews exist.
- [ ] Update site guides, llms.txt, README and GitHub links; update sitemap `lastmod` for changed pages.
- [ ] Publish release notes/changelog and launch announcements when requested; use [Launch channels](#launch-channels).
- [ ] Check support inbox and crash reports after release.

## After launch

- [ ] Submit selfh.st, AlternativeTo and other relevant listings; follow up on awesome-jellyfin.
- [ ] Apply to jellyfin.org only after its eligibility requirements are met; gather traction evidence first. See [Getting listed](#getting-listed).
- [ ] Monitor crashes, reviews and support; prioritize a maintenance update from actual findings.
- [ ] Consider a well-timed in-app rating prompt, screenshot experiments, press outreach and appropriate In-App Events.
- [ ] Track acquisition and search visibility using [Metrics](#metrics); publish dated changelogs.

## QA evidence and deferred scope

### QA-8 privacy slice — November 6, 2026

Scope: source-level privacy/data-flow review and small fixes only. No packet capture, credentials inspection, full security review, dependency vulnerability audit, App Store Connect edits or upload. The live policy URL returned HTTP 200; policy changes below are local until deployed.

| Surface | Findings / disposition |
|---|---|
| App required-reason APIs | `SessionStore`, app preferences and feature stores use standard UserDefaults: existing `CA92.1` fits. `WidgetBridge` reads modification dates in the app-group container; music/podcast downloads read local file sizes: existing `C617.1` fits. No first-party disk-capacity, boot-time or active-keyboard API use found. No manifest changes needed |
| Widget | `WidgetStore` shares JSON/artwork files, not App Group UserDefaults. No direct required-reason APIs found in widget/shared code; empty API list retained. App-group entitlement alone does not require a UserDefaults reason |
| Dependencies | Inspected resolved packages and existing November 6 archive: app, widget, GRDB and NIOPosix manifests are packaged. GRDB declares no collected data; NIOPosix declares file timestamp wrapper reason `0A2A.1`. Nuke caches local image files (app container metadata covered by `C617.1`). Get/Jellyfin SDK provide requested networking; Inject's runtime injection is under DEBUG. No analytics/advertising SDK found. Recheck Xcode's aggregate privacy report on the final distribution archive |
| Jellyfin | Authentication, library requests, playback reporting, edits and cover uploads go to the selected server. `ClientIdentity` sends app/version, device name and a stable random Keychain identifier. Server operator retention is outside the developer's control |
| Podcasts | Apple directory receives queries/chart requests. Publisher/CDN hosts receive feed, audio, artwork, chapter and transcript requests, including IP addresses. Podcast request configuration separates Jellyfin credentials. `PodcastSyncState` syncs public feed URLs, enabled state, episode IDs, positions and played timestamps to Jellyfin; only recognized private feed URLs are excluded, not a blanket promise that all private-podcast activity stays local |
| Local storage / deletion | Session token and random device ID use Keychain; library, downloads, preferences and widget snapshots are local. Sign-out clears account caches/downloads/token but retains some preferences/device ID. Removed inaccurate uninstall-erases-everything claim; server-side history is not deleted by uninstall/sign-out |
| Policy access | Shared native `PrivacyPolicyLink` in Settings → About and initial sign-in form, opening the HTTPS policy in the browser. No session details/query parameters included |

**Privacy-label assessment:** no developer-operated collection, tracking or advertising integration was found in the reviewed code. “Data Not Collected” remains the proposed label, not a certified answer based merely on an empty manifest. Apple defines collection in terms of retention by the developer or third-party partners; Apple-service collection is handled separately. Before submitting, confirm whether any configured third-party service is a developer partner retaining app-user data, rather than a user-selected server/content host; disclose applicable categories if so. Do not represent podcast requests or Jellyfin playback history as staying entirely on-device. App Store Connect answers were not inspected or changed.

**Policy corrections:** describe Jellyfin client identifiers, uploaded covers, podcast search/content requests and progress sync; distinguish local deletion from Keychain/server retention; explain external links and voluntary support contact. These clarify existing behavior and do not introduce telemetry.

**Verification:** Release simulator build succeeded (arm64 + x86_64, existing compiler warnings); app/widget manifests pass plist validation and match their packaged copies. GRDB and NIOPosix manifests are present and parse successfully in the built app. Sitemap XML and `git diff --check` passed. Live policy URL returned HTTP 200. Manual VoiceOver/browser-opening smoke check remains for QA-6. Publish the policy changes with the site before submitting the app.

Sources: [Apple required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [Apple privacy-label definitions](https://developer.apple.com/app-store/app-privacy-details/). Source evidence: `App/PrivacyInfo.xcprivacy`, `Widgets/PrivacyInfo.xcprivacy`, `JellyfinKit/{ClientIdentity,SessionStore}.swift`, `Features/Widgets/WidgetBridge.swift`, `Podcasts/{DirectoryClient,PodcastSync}.swift`, `Features/{AppModel,Podcasts/PodcastsStore}.swift`, `WidgetShared/WidgetSnapshots.swift` (paths under `Packages/WavetileKit/Sources/` where applicable).


**QA-1, November 5 (imported record):** 94/94 package tests under both Address Sanitizer and Thread Sanitizer, no reports. The 17 UI tests were exercised under ASan, TSan and plain runs with no sanitizer reports; earlier functional failures were not sanitizer bugs. Final plain run: **17/17**. This does not claim all sanitized UI runs passed functionally or that all manual device testing is complete.

Fixes committed in `92cc0cb`: splash is a modal accessibility element and stops intercepting touches before fading; album/episode download controls retain VoiceOver labels inside menus; performance budgets are skipped under sanitizers. User-approved audit exceptions: one-line names (tile artist and Now Playing title/artist) and element-less contrast findings for album rows beneath the glass tab bar. Reassess if those layouts change. Later splash and Home-refresh changes are included in the November 6 candidate and need relevant regression coverage.

The original November 4 inventory was 111 tests (94 package + 17 UI), five UI suites, no CI or lint, and gaps around Downloads/Persistence/Features. This is historical, not a current coverage measurement. Useful test logging: use `XCTContext.runActivity(named:)` when print output is absent from result bundles; inspect bundles using `xcrun xcresulttool get test-results`.

**Older readiness items now resolved:** app icon/launch artwork, developer signing/team, App Group/app record, matching app/widget versions, encryption declaration and first TestFlight upload. Rive was removed October 24; no release work remains for it. CarPlay capability was enabled October 30. InjectionNext companion setup is developer convenience, not a release gate.

**October 24 nonblocking backlog — revalidate before scheduling:** offline-play reporting to Jellyfin, incremental library sync, multi-account support, collection rename and AudioPlayer engine tests. Do not infer these are still missing from an old note; engine coverage is explicitly assessed in QA-4. iPhone/portrait-only support is intentional.

## Marketing reference

Goal: when someone searches or asks an LLM for “a Jellyfin music app for iPhone”, Wavetile is in the answer. The sections below hold copy and channel details; completion status lives in the phase checklists above.

## Positioning
Use one line, word for word, everywhere (App Store, site, GitHub, posts):

> **Wavetile: your Jellyfin music and your podcasts, in one app.**

| Differentiator | Proof point |
|---|---|
| Native, iOS 26 design | SwiftUI, Liquid Glass, widgets, Live Activity |
| Fast and offline | Full local library mirror; the first frame comes from the device |
| Gapless playback | AVQueuePlayer queue |
| Podcasts built in (optional) | Directory, OPML, chapters, transcripts, synced through Jellyfin |
| Private | No Wavetile account or analytics; music connects to your Jellyfin server. Optional podcasts also connect to Apple’s directory and podcast hosts |

Spell the name **Wavetile**: one word, capital W only. "Wave tile" brings up flooring and acoustic panels.

## App Store (ASO)
| Field | Limit | Draft |
|---|---|---|
| Name | 30 | `Wavetile Music` (current App Store Connect name). Keep "Jellyfin" out of the name: Jellyfin's [branding guidelines](https://jellyfin.org/docs/general/contributing/branding/) ask third-party apps not to use it, which would block the jellyfin.org listing. Reference it in the subtitle and description instead |
| Subtitle | 30 | `Music & podcasts for Jellyfin` |
| Keywords | 100 | `selfhosted,offline,gapless,player,flac,audio,library,radio,carplay,widget,opml,homelab,nas,stream` |
| Category | | Music (primary), Entertainment (secondary) |
| Privacy label | | "Data Not Collected" if that's still true. It's a selling point |

Keyword rules: separate with commas and no spaces, and don't repeat words that are already in the name or subtitle (Apple indexes those too). Never use competitor trademarks (Plex, Emby, Spotify); App Review rejects them.

**Screenshots** (the first 3 count most): 1. Home feed: "Your Jellyfin library, beautifully". 2. Now Playing: "Gapless, offline, lossless". 3. Downloads/offline. 4. Podcasts. 5. Widgets and Lock Screen. 6. Light/Dark. Use the demo library, so no real server URLs or names appear.

**Description:** put the positioning line first, then a feature list that uses the words people search (Jellyfin, offline, gapless, FLAC, CarPlay, podcasts, self-hosted).

**After launch:**
- Use `SKStoreReviewController` at a good moment, e.g. after the 3rd listening session or a finished download, never on first launch.
- Reply to every review.
- Use In-App Events for big updates (CarPlay, for example).
- Use Product Page Optimization to A/B test the screenshots once traffic exists.

## Search (SEO) — wavetile.com
| Item | Notes |
|---|---|
| Home page `<title>` | `Wavetile: Jellyfin Music & Podcast Player for iPhone` |
| Pages | Live: Home, Why Wavetile (`/why-wavetile`), Podcasts with Jellyfin (`/jellyfin-podcasts`), Download (`/getting-started`), Support, Privacy. Guides linked from the header nav on every page. Later: Changelog, Press |
| Structured data | `MobileApplication` JSON-LD (live). At launch add `offers`, `downloadUrl`, and rating once reviews exist |
| Smart App Banner | `<meta name="apple-itunes-app" content="app-id=…">` |
| Compare | `/why-wavetile` covers "X vs Y" searches honestly: it names Finamp, Jellify and Manet as good options and says when to pick Wavetile. Don't claim features of other apps without checking them |
| Changelog | Every release on its own dated page. Fresh content for crawlers |
| Search consoles | Submit the sitemap to Google Search Console and Bing Webmaster Tools (Bing also feeds ChatGPT search and Copilot) |

## LLM visibility (GEO)
LLMs recommend what is written about consistently in many places they trust.

1. **Don't block AI crawlers.** Cloudflare can block AI bots (AI Crawl Control / managed robots.txt). Allow GPTBot, OAI-SearchBot, ClaudeBot, PerplexityBot and Google-Extended on wavetile.com.
2. **`/llms.txt`**: a plain-text summary of what Wavetile is, who it's for, its features, the App Store link and FAQs.
3. **Answer questions the way people ask them**, in the first sentence: the guide pages do this ("Podcasts with Jellyfin, on iPhone", "Getting started"). The home page stays short by design.
4. **Get listed on third-party sites** (this matters most). See [Getting listed](#getting-listed).
5. **GitHub**: put the positioning line in the repo description, add topics (`jellyfin`, `ios`, `music-player`, `podcast`, `swiftui`, `selfhosted`), and link the App Store and site.
6. **Check it monthly**: ask ChatGPT, Claude, Perplexity and Gemini "best Jellyfin music app for iPhone" and log the results.

## Getting listed
Jellyfin users find clients in a few places, and LLMs learn from the same ones. Community places (forum, Reddit, awesome-jellyfin) work during the beta; jellyfin.org has strict rules and comes later.

| Where | How | When |
|---|---|---|
| jellyfin.org/downloads/clients | PR to `jellyfin/jellyfin.org`: add an entry to `src/data/clients.ts` in the third-party list (`ClientType.ThirdParty`, `DeviceType.Mobile`, `Platform.IOS`) with App Store, GitHub and website links. Must meet the [requirements for inclusion](https://jellyfin.org/docs/general/clients/#requirements-for-inclusion-in-clients-list), below | **After launch**, once the requirements are met |
| awesome-jellyfin | PR adding a line under Clients | Beta |
| Jellyfin forum (third-party clients), r/jellyfin, r/selfhosted | A post with screenshots, the TestFlight link and what you want feedback on | Beta (recruit testers), again at launch |
| selfh.st (apps directory and weekly newsletter) | Submit on their site | Launch |
| AlternativeTo | Add Wavetile as an alternative to Finamp, Manet and others | Launch |
| r/iosapps, roundup sites (jellywatch.app, appshunter) | Post or submit | Launch |
| ~~awesome-selfhosted~~ | Skip: it lists self-hostable server software, not client apps | — |

**jellyfin.org requirements** (all must be met; the Jellyfin team decides, and client PRs often wait months for review):

| Requirement | Wavetile (2026-10-29) |
|---|---|
| Server URL configurable, Jellyfin as a first-class citizen | Met |
| Free and open source under an FSF-listed license | Met: MPL-2.0 since 2026-10-29 |
| Traction: 1 year of active development, or significant user interest as judged by the team | **Not met:** development started 2026-10-23. Build the user-interest case: TestFlight and App Store numbers, forum and Reddit threads, GitHub stars |
| A unique feature, live in a public release | Podcasts built in. Strongest once it's on the App Store |
| Follow the community standards and branding guidelines | No "Jellyfin" in the app name, no Jellyfin logo shape in the icon |

**Draft entry** for the end of `thirdPartyClients` in `src/data/clients.ts` (fill in the App Store ID at launch; their style is one line of plain description, no marketing):

```ts
  {
    id: 'wavetile',
    name: 'Wavetile',
    description:
      'A native iPhone music player with a full podcast player built in: gapless playback, offline downloads and podcast subscriptions synced through Jellyfin.',
    clientType: ClientType.ThirdParty,
    deviceTypes: [DeviceType.Mobile],
    platforms: [Platform.IOS],
    primaryLinks: [
      {
        id: 'app-store',
        name: 'App Store',
        url: 'https://apps.apple.com/app/idXXXXXXXXXX'
      }
    ],
    secondaryLinks: [
      {
        id: 'github',
        name: 'GitHub',
        url: 'https://github.com/derrellwilliams/wavetile'
      },
      {
        id: 'website',
        name: 'Website',
        url: 'https://wavetile.com'
      }
    ]
  }
```

PR description: what Wavetile is, the unique feature (podcasts alongside music, synced through Jellyfin preferences), the license, and evidence of user interest (testers, ratings, community threads). Expect to be asked about each requirement.

**Before opening any listing PR:** the repo should be ready for a maintainer's quick look (license, a user-facing README with the beta link and screenshots, topics). Say "(beta)" in descriptions so people expect a few rough edges. Ship the newest TestFlight build first.

## Launch channels
| Channel | When | Angle |
|---|---|---|
| TestFlight public beta link (site hero, r/jellyfin, r/selfhosted) | As soon as Beta App Review approves | Recruit testers, collect quotes, fix bugs |
| r/jellyfin, r/selfhosted | Launch day | Lead with screenshots, a dev's story, and "what I'd love feedback on" |
| Show HN | Launch week | Technical angle: GRDB mirror, 50k-track performance, gapless |
| selfh.st weekly newsletter | Launch week | Submit the app |
| Product Hunt | Launch week (Tue–Thu) | Visual gallery |
| Mastodon / Bluesky (#jellyfin, #selfhosted) | Ongoing | Short clips of motion and widgets |
| iOS blogs / YouTubers (MacStories, 9to5Mac, homelab channels) | After the first reviews | Press kit + promo codes |

**Press kit** (`wavetile.com/press`): icon, screenshots, a 30-second video, a one-paragraph description, a contact.

## Metrics
| Metric | Where |
|---|---|
| Impressions → page views → downloads | App Store Connect Analytics |
| Search terms people used | App Store Connect → Acquisition |
| Rating and review count | App Store Connect |
| Site traffic and queries | Search Console, Cloudflare Web Analytics (cookieless) |
| LLM mentions | Monthly manual check (above) |

## Security
- **App Review demo server:** a separate Jellyfin instance with a non-admin, read-only account and only royalty-free/public-domain music. Expect the credentials to leak, and keep it away from your personal server.
- **Screenshots and videos:** no real server addresses, usernames or tokens.
- **Privacy claims** must match the app. "Data Not Collected" is wrong if you add analytics or crash reporting later.
- **Site:** HTTPS only. Use HSTS once it's stable, and set no third-party trackers if you're advertising privacy.
