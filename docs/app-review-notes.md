# App Review notes — updated November 8, 2026

Not submitted. Reviewer access uses the public Jellyfin demo server (decision in [LAUNCH.md](LAUNCH.md)). Device verification was signed off by the tester on 2026-11-08.

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

The app has no analytics, ads or tracking.
Privacy: https://wavetile.com/privacy
Support: https://wavetile.com/support
Contact: realslimscrawny@gmail.com
```

## Before submitting

- The demo is not ours: it can reset, change or go down during review. Recheck it (server up, `demo` login works, albums play) just before submitting.
- Enter the contact name and phone in App Store Connect.
- Confirm the final build number in LAUNCH.md.
