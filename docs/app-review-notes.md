# App Review notes — reviewed November 7, 2026

Reviewed against source and Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/). Not submitted. Fill the fields below in App Store Connect; do not commit passwords here. Device verification is tracked in [testparty.md](testparty.md).

## App Review Information fields

| Field | Prepared value / outstanding requirement |
|---|---|
| Sign-in required | Yes |
| Username / password | Dedicated reviewer account; enter directly in App Store Connect |
| Server URL | Pending isolated server setup; see [reviewer-server.md](reviewer-server.md) |
| Contact email | realslimscrawny@gmail.com |
| Contact first/last name and phone | Account owner must supply in App Store Connect |
| Build | Final tested RC; record in LAUNCH.md |

## Notes for the reviewer

Copy this block after replacing the server placeholder and confirming the demo account permissions and media licenses:

```text
Wavetile is an independent music and podcast player for iPhone. It requires a Jellyfin server account. It provides no music catalog or server hosting and has no separate Wavetile account.

Demo server: <REVIEW_SERVER_HTTPS_URL>
Use the username and password supplied in App Review Information. This isolated server contains licensed demo music. The account permits browsing, playback and downloads but not server administration or media deletion.

Sign in: launch Wavetile, enter the server address above, then enter the supplied username and password and tap Sign In. Allow the initial library sync to finish. Use these credentials rather than Quick Connect, which requires authorization from another signed-in Jellyfin device.

Music: open the Music tab, choose an album and play a track. Open the album menu to download it, then find it in Downloaded. Downloads default to MP3 at 256 kbps. To request original files, open the top-right profile avatar, then Downloads and select Original (lossless when possible).

Podcasts: open the top-right profile avatar and enable podcasts in the Podcasts settings section. On the Podcasts tab, use + and Search Apple Podcasts to find and follow a show. Episodes come from publisher feeds, not the Jellyfin music library. Podcasts are off by default for a new account on this device.

Background modes: audio supports playback with the screen locked or the app in the background; fetch supports opportunistic podcast refresh through com.derrellwilliams.wavetile.podcast-refresh. Refresh timing is controlled by iOS.

CarPlay: sign in on the iPhone first. CarPlay provides Home, Playlists and Library, plus a Podcasts tab when enabled, using the system Now Playing screen. The app has the CarPlay Audio entitlement. Home Screen widgets and a download Live Activity are also included.

Networking: remote server sign-in requires HTTPS, except that the app permits HTTP for local-network addresses and .ts.net hostnames. Local Network permission supports access to home servers. The media ATS exception supports podcast audio from HTTP publishers. Use the HTTPS demo URL above for review.

Privacy: no analytics, advertising or tracking SDK is included. The app contacts the chosen Jellyfin server, Apple's podcast directory/charts and podcast publishers. The server receives session/client identifiers, playback reports and supported library/podcast changes. Podcast hosts receive content requests. Publishers may include ads in episodes.

There are no in-app purchases or subscriptions implemented in this build.
Privacy: https://wavetile.com/privacy
Support: https://wavetile.com/support
Contact: realslimscrawny@gmail.com
```

## Submission dependencies

- Populate the HTTPS demo URL and App Store Connect credentials after the isolated server is ready. If a blank password is intentionally used, explain it explicitly; a dedicated nonblank password is preferred.
- Confirm final build and testparty results before describing this block as verified on the submitted binary.
- Confirm price in App Store Connect. No “free app” assertion is made here because pricing was not inspected.
- Keep the server reachable throughout review and any appeal. The public Jellyfin demo is a fallback only, not a server whose uptime or library we control.

## Corrections from the earlier draft

Settings is opened by the top-right avatar. CarPlay's tab is labelled Podcasts (its template title is Up Next). Original downloads are optional; default MP3 downloads are not lossless. Quick Connect is an alternative authorization flow, not inherently impossible for reviewers. HTTP host classification and Tailscale naming do not prove that credentials can never leave the intended origin: redirect verification remains in testparty. Source configuration establishes feature intent, not successful device behavior.
