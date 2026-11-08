# App Store privacy answers (worksheet)

Draft written 2026-11-07 from the source and the Nov 6 review in [qa-evidence.md](qa-evidence.md#qa-8-privacy-slice--november-6-2026). Nothing was entered in App Store Connect and its current form wasn't inspected, so recheck the questions against Apple's [privacy details](https://developer.apple.com/app-store/app-privacy-details/) when filling them in. Final sign-off still needs Xcode's aggregate privacy report on the release archive (Organizer → archive → Generate Privacy Report).

## Proposed answers

| App Store Connect question | Proposed answer | Basis |
|---|---|---|
| Do you or your third-party partners collect data from this app? | **No** → label "Data Not Collected" | The developer runs no server, analytics, advertising, crash reporter or attribution SDK; nothing is sent to the developer or to a partner who retains it for them (see "What leaves the device") |
| Tracking (ATT) | **No** | `NSPrivacyTracking` is false, no tracking domains, no IDFA use, no data shared with brokers or ad networks |
| Privacy policy URL | `https://wavetile.com/privacy` | Local edits (Nov 6 wording fixes, in-app links) must be deployed first; the live page was HTTP 200 but is the old text |
| User privacy choices URL | Leave blank | No account or data-deletion flow of ours to point to |
| Contact for privacy questions | realslimscrawny@gmail.com | Same as site and support |

This is a judgment, not a certainty: Apple counts data as collected when the developer or a partner retains it, and the user's own Jellyfin server and podcast publishers are chosen and operated by the user or third parties, not the developer. If you'd rather err on the side of disclosure, the closest-fit alternatives are listed under "If you disclose instead".

## What leaves the device

| Destination | What is sent | Who operates it | Why it isn't developer collection |
|---|---|---|---|
| The user's Jellyfin server | Username and password (sign-in only), access token, library and playback requests, play reports (offline plays are queued in `pendingPlay` and sent later), favorites/playlist/collection edits, uploaded covers, podcast subscription and progress sync, and a client identity: app name and version, device name, and a random per-install device ID (Keychain) | The user or their host | Chosen by the user; the developer never sees it. State this in the policy, and in the review notes that the server's retention is the operator's |
| `itunes.apple.com`, `rss.marketingtools.apple.com` | Podcast search text, show lookups by ID, top-chart requests by country, and (for Recommended for You) only a show title and genre IDs; plus the device's IP address, as with any request | Apple | Apple-service request made on the user's action; not retained by us |
| Podcast publishers' and CDNs' hosts | Feed, audio, artwork, chapters and transcript requests, with the device's IP address and a User-Agent. No Jellyfin credentials (separate request configuration) | Third-party publishers | Content hosts the user chose by following a show |
| Safari | Privacy policy, support and external links open in the browser, not in the app | n/a | Not the app's traffic |

On device only: library and podcast databases, downloads, preferences, widget snapshots (app-group files), Keychain items (session token, device ID). Sign-out clears the account's caches, downloads and token; the device ID and some preferences stay. Uninstall doesn't delete anything on the server.

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

## If you disclose instead

Only if you decide Apple would treat the Jellyfin client identity or podcast requests as collected. Each would be "not linked to you, not used for tracking":

| Data type | Where it applies | Purpose |
|---|---|---|
| Identifiers → Device ID | Random per-install ID sent to the user's Jellyfin server | App Functionality |
| Usage Data → Product Interaction | Play reports and progress sync to the user's server | App Functionality |
| User Content → Other User Content | Uploaded cover art, playlists, collections | App Functionality |

I recommend "Data Not Collected" because none of this reaches the developer.

## Before you enter them

- [ ] Deploy the corrected policy and re-fetch https://wavetile.com/privacy to confirm the new text is live.
- [ ] Re-read App Store Connect's current questions; the wording above follows Apple's published definitions as of the Nov 6 review.
- [ ] Generate the privacy report on the final archive and confirm it lists no unexpected SDK or data type.
- [ ] If analytics or crash reporting is ever added, this answer becomes wrong; change it in the same release.
- [ ] Record the date you entered the answers in [LAUNCH.md](LAUNCH.md).

## Related submission answers (for the same sitting)

| Question | Proposed answer | Notes |
|---|---|---|
| Export compliance | Uses only exempt encryption (HTTPS/OS crypto) | `ITSAppUsesNonExemptEncryption = false` is already set in `project.yml`, so uploads skip the prompt |
| Age rating | Check the current questionnaire; likely low, with a **third-party content** note | The app plays user-supplied music and podcasts from publishers the user follows, so episodes can contain mature themes. It has no browser, but external links open in Safari. Answer from Apple's current form and decide how to treat podcasts rather than reusing this guess |
| Content rights | Yes, third-party content is the user's own | The app ships no media; the reviewer server holds only royalty-free/public-domain music (keep the license notes) |
| In-app purchases / ads | None | |
