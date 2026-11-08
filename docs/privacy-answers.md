# App Store privacy answers (worksheet)

Reviewed 2026-11-07 from the source and the Nov 6 review in [qa-evidence.md](qa-evidence.md#qa-8-privacy-slice--november-6-2026). Nothing was entered in App Store Connect and its authenticated form wasn't inspected. Apple's public definitions were rechecked Nov 7; reconcile the fields with [privacy details](https://developer.apple.com/app-store/app-privacy-details/) when filling them in. Final sign-off still needs Xcode's aggregate privacy report on the release archive (Organizer → archive → Generate Privacy Report).

## Proposed answers

| App Store Connect question | Proposed answer | Basis |
|---|---|---|
| Do you or your third-party partners collect data from this app? | **Proposed No**, conditional on the service/partner confirmation below | No analytics, advertising, crash-reporting or attribution SDK was identified in the reviewed app. Confirm actual service relationships and retention before choosing No; source alone cannot establish them |
| Tracking (ATT) | **No** | `NSPrivacyTracking` is false, no tracking domains, no IDFA use, no data shared with brokers or ad networks |
| Privacy policy URL | `https://wavetile.com/privacy` | Verified Nov 7: HTTP 200 and the live main content exactly matches the corrected local policy |
| User privacy choices URL | Leave blank | No account or data-deletion flow of ours to point to |
| Contact for privacy questions | realslimscrawny@gmail.com | Same as site and support |

Apple's definition concerns off-device transmission that lets the developer or a third-party partner access data beyond servicing the request in real time. It is not enough that the developer personally does not see the data. Apple says its own collection need not be disclosed by the app developer. These answers are an engineering assessment, pending confirmation of service relationships and the final archive, not a certification from the manifest. [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

Before selecting No, confirm there is no developer-arranged analytics, publisher, hosting or other partner retaining app-user data. Review normal website/support retention separately, including Apple's optional-disclosure conditions for voluntary support. An isolated reviewer-only demo server must not silently become a public service for app users without reassessing these answers.

## What leaves the device

| Destination | What is sent | Who operates it | Assessment / boundary |
|---|---|---|---|
| The user's Jellyfin server | Username and password (sign-in only), access token, library and playback requests, play reports (offline plays are queued in `pendingPlay` and sent later), favorites/playlist/collection edits, uploaded covers, podcast subscription and progress sync, and a client identity: app name and version, device name, and a random per-install device ID (Keychain) | The user or their host | User-selected host; its operator retains account-linked history. Confirm it is not a developer partner/service. A developer-operated demo is a separate limited review setup |
| `itunes.apple.com`, `rss.marketingtools.apple.com` | Podcast search text, show lookups by ID, top-chart requests by country, and (for Recommended for You) only a show title and genre IDs; plus the device's IP address, as with any request | Apple | Apple services; requests may also occur during recommendations/chart refresh. Apple collection is treated separately by its guidance |
| Podcast publishers' and CDNs' hosts | Feed, audio, artwork, chapters and transcript requests, with the device's IP address and a User-Agent. No Jellyfin credentials (separate request configuration) | Third-party publishers | Content hosts may also receive artwork requests while browsing/searching before a follow. Their logging and any partner relationship must be assessed |
| Safari | Privacy policy, support and external links open in the browser, not in the app | n/a | Website hosting receives requests; voluntary support contact can reach the developer. Review the applicable disclosure conditions |

On device only: library and podcast databases, downloads, preferences, widget snapshots (app-group files), Keychain items (session token, device ID). Sign-out clears account caches and downloads and attempts token deletion. If iOS refuses deletion, cleanup is retried and that session cannot restore meanwhile. The device ID and some preferences remain; Keychain entries may survive uninstall. Remote session revocation is best effort, and uninstall does not delete server data.

## Manifest and SDKs

| Item | Result |
|---|---|
| `App/PrivacyInfo.xcprivacy` | Tracking false; no collected-data types; UserDefaults `CA92.1`, file timestamp `C617.1` |
| `Widgets/PrivacyInfo.xcprivacy` | Empty API list; shares JSON/artwork files, not App Group UserDefaults |
| GRDB | Manifest declares no collected data |
| NIOPosix (via the Jellyfin SDK) | File-timestamp reason `0A2A.1` |
| Nuke | Local image cache only (covered by `C617.1`) |
| Get, jellyfin-sdk-swift | Networking only |
| Inject | Runtime injection compiled under DEBUG only |
| Analytics, ads, crash reporting | None found (searched `StoreKit`, `requestReview`, analytics, crashlytics, sentry, telemetry on Nov 7: no matches) |

## If retained data must be disclosed

Do not choose disclosure categories as a preference or default them all to “not linked.” Reassess actual recipients and retention. Jellyfin requests use a signed-in account and stable client identifier, so retained data may be linked to the user. Tracking is a separate question.

| Candidate data | Reassess if a developer/partner retains it |
|---|---|
| User ID / Device ID | Account and client identifiers used for app functionality |
| Product Interaction | Listening history and progress |
| Other User Content / relevant media category | Playlists, subscriptions or uploaded cover images, according to the actual data and current form |
| Search History | Retained searches outside Apple-only collection |
| Contact Info / support content | Developer support collection, subject to Apple's optional-disclosure criteria |

Select exact types, purposes, identity linkage and tracking from the verified flow, not this candidate table alone.

## Before you enter them

- [x] Nov 7: fetched the live privacy policy; its main content matches the corrected local policy. Support also returns HTTP 200.
- [x] Nov 7: rechecked Apple's public privacy definitions.
- [ ] Confirm service/partner retention and reconcile the authenticated App Store Connect form before entry.
- [ ] Generate the privacy report on the final archive and confirm it lists no unexpected SDK or data type.
- [ ] If analytics, crash reporting or any new retaining service is added, reassess disclosure in the same release.
- [ ] Record the date you entered the answers in [LAUNCH.md](LAUNCH.md).

## Related submission answers (for the same sitting)

| Question | Proposed answer | Notes |
|---|---|---|
| Export compliance | Uses only exempt encryption (HTTPS/OS crypto) | `ITSAppUsesNonExemptEncryption = false` is already set in `project.yml`, but confirm the final binary and applicable App Store Connect questionnaire; this flag alone is not a legal determination |
| Age rating | Complete the current questionnaire; no rating is preselected | The app plays user-supplied music and podcasts from publishers the user follows, so episodes can contain mature themes. It has no browser, but external links open in Safari. Answer from Apple's current form and decide how to treat podcasts rather than reusing this guess |
| Content rights | Third-party content is accessible; confirm the rights declaration against actual permissions | The app ships no media; the planned reviewer server must use licensed media with recording, composition and artwork evidence (see reviewer-server.md) |
| In-app purchases / ads | None | |
