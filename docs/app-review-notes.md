# App Review notes — updated November 11, 2026

Submitted Nov 11, 2026 (build 202611110730); this text is what is in App Store Connect. Reviewer access uses the public Jellyfin demo server (decision in [LAUNCH.md](LAUNCH.md)).

## App Review Information fields

| Field | Value |
|---|---|
| Sign-in required | Yes |
| Username | `demo` |
| Password | Leave blank (the demo account has no password; the notes say so) |
| Contact email | realslimscrawny@gmail.com |
| Contact first/last name and phone | Account owner supplies in App Store Connect |
| Build | Final tested RC; record in LAUNCH.md |

## Notes for the reviewer

```text
Wavetile is an independent music and podcast player for iPhone. It needs a Jellyfin server account and has no catalog of its own and no Wavetile account. There are no in-app purchases or subscriptions, and the app is free.

Sign in: open Wavetile, enter the server address https://demo.jellyfin.org/stable, username demo, and leave the password blank (the public demo account has no password). Tap Sign In and let the first library sync finish. This is Jellyfin's public demo server, so its music library is small.

Music: open the Music tab, choose an album and play a track. Use the album menu to download it, then find it in Downloaded.

Podcasts (optional, off by default): tap the top-right profile avatar and turn on podcasts. On the Podcasts tab, tap + to search for and follow a show.

Background audio plays with the screen locked. CarPlay is supported (sign in on the iPhone first).

Network security: Jellyfin servers must use HTTPS, except servers on the user's local network or a Tailscale tailnet (ts.net), which are home setups that rarely have certificates. The app refuses a plain-HTTP server anywhere else at sign-in, so the access token never crosses the internet in cleartext. The media-only ATS exception (NSAllowsArbitraryLoadsInMedia) exists because some podcast publishers still serve episode audio over HTTP; no Jellyfin credentials are sent to podcast hosts.

Background modes: "audio" keeps music and podcasts playing with the screen locked; "fetch" lets iOS wake the app to check followed podcasts for new episodes. The CarPlay Audio entitlement was granted by Apple on 2026-10-30. Live Activities are used only to show download progress.

Podcasts are optional and off by default. Show search uses Apple's public iTunes Search API; episodes stream from each publisher's own feed.

If the demo server is unreachable, tell us in the review reply and we will provide another account at once. The app is a client only and does not work without a Jellyfin server.

The app has no analytics, ads or tracking.
Privacy: https://wavetile.com/privacy
Support: https://wavetile.com/support
Contact: realslimscrawny@gmail.com
```

## While in review

- The demo is not ours: it can reset, change or go down. If the reviewer can't sign in, reply with another account (see [reviewer-server.md](reviewer-server.md)).
