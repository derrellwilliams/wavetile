# App Store listing — prepared November 7, 2026

Copy reviewed against source; not entered in App Store Connect. Final build and device sign-off remain in [LAUNCH.md](LAUNCH.md) (device checks signed off 2026-11-08). Pricing, territories and category selection still need account confirmation.

## Fields

| Field | Copy |
|---|---|
| Name | Wavetile Music |
| Subtitle | Music & podcasts for Jellyfin |
| Keywords | selfhosted,offline,gapless,player,flac,audio,library,radio,carplay,widget,opml,homelab,nas,stream |
| Primary category | Music |
| Secondary category | Entertainment |
| Support URL | https://wavetile.com/support |
| Privacy policy URL | https://wavetile.com/privacy |
| Marketing URL | https://wavetile.com |

Name: 14/30 characters; subtitle: 29/30; keywords: 97/100 bytes. Promotional text: 139/170 characters; description: 1,680/4,000 characters. Both support and privacy URLs returned HTTP 200 on Nov 7; the live policy's main content matches `site/privacy.html`.

## Promotional text

Your music server, your listening space. Stream your Jellyfin library, download music for offline listening, and bring your podcasts along.

## Description

Wavetile: your Jellyfin music and your podcasts, in one app.

Connect to your Jellyfin server and enjoy your music library on iPhone. A Jellyfin server and an account on that server are required. Wavetile does not include a music catalog or provide server hosting.

YOUR LIBRARY, READY TO PLAY
Browse albums, artists, playlists and collections. Return to recently played favorites, explore your most-played music, or start a radio queue using Jellyfin Instant Mix.

LISTEN ONLINE OR OFFLINE
Stream supported formats including FLAC and ALAC, with gapless playback. Download music for listening without a connection. Downloads default to MP3 at 256 kbps; choose Original in Settings to preserve the source format when available. Playback quality depends on the source, server and output route.

PODCASTS WHEN YOU WANT THEM
Turn on optional podcasts to search Apple's podcast directory, follow shows, download episodes and manage your Up Next queue. Import subscriptions with OPML. Chapters and transcripts are available when supplied by the publisher.

AT HOME AND ON THE ROAD
Use CarPlay, AirPlay, Lock Screen controls and Home Screen widgets. Keep listening with the screen locked or the app in the background.

MADE FOR YOUR IPHONE
Choose light or dark appearance. Your cached library and downloaded audio stay available when your server is out of reach.

Wavetile includes no advertising or analytics SDKs. Podcast publishers may include advertisements in their content. Your chosen server and podcast services receive the requests needed for playback and sync; see the privacy policy for details.

Wavetile is an independent app and is not affiliated with the Jellyfin project.

## Screenshot captions

1. Your Jellyfin library, beautifully
2. Your music. Your queue.
3. Download now. Listen offline.
4. Your podcasts, alongside your music
5. Control playback at a glance
6. Light or dark. Your choice.

Use only the licensed demo library and fictional account details. No real server addresses or tokens. Screenshots still need production; these are captions, not completed assets. Avoid the old “Gapless, offline, lossless” caption because default downloads are lossy.

## Source and submission checks

Feature sources: `JellyfinKit/PlaybackAPI.swift`, `Downloads/DownloadManager.swift`, `Features/Settings/SettingsDrawer.swift`, `Features/Podcasts/PodcastsStore.swift`, `Features/CarPlay/CarPlayController.swift`, `Widgets/`. Device claims remain gated by the device pass; remove any claim that fails final RC verification. No price or guaranteed audio fidelity is claimed.

Field limits checked against [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) and [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/). Keep Jellyfin out of the app name under its [branding guidance](https://jellyfin.org/docs/general/contributing/branding/); subtitle use describes compatibility, not endorsement.
