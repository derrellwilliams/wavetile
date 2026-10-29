# Wavetile launch & growth plan

The goal: when someone searches or asks an LLM for "a Jellyfin music app for iPhone", Wavetile is in the answer.

## Status (2026-10-29)
| Area | State |
|---|---|
| wavetile.com | Live on Vercel (`site/`, auto-deploys on push), DNS on Cloudflare (DNS only), HTTPS |
| Pages | Home, Why Wavetile, Podcasts with Jellyfin, Download, Support, Privacy |
| TestFlight | Build 202610281900 approved for the external "public beta" group; public link https://testflight.apple.com/join/pk9dyfMq |
| App Review login | Jellyfin's public demo: `https://demo.jellyfin.org/stable`, user `demo`, blank password (any typed password fails) |
| Contact | realslimscrawny@gmail.com (site, support and privacy pages) |
| Next | Request the CarPlay entitlement; ship a new TestFlight build; get listed on jellyfin.org; recruit testers (r/jellyfin, r/selfhosted) |

## Positioning
Use one line, word for word, everywhere (App Store, site, GitHub, posts):

> **Wavetile: your Jellyfin music and your podcasts, in one app.**

| Differentiator | Proof point |
|---|---|
| Native, iOS 26 design | SwiftUI, Liquid Glass, widgets, Live Activity |
| Fast and offline | Full local library mirror; the first frame comes from the device |
| Gapless playback | AVQueuePlayer queue |
| Podcasts built in (optional) | Directory, OPML, chapters, transcripts, synced through Jellyfin |
| Private | No accounts, no analytics, talks only to your server (confirm before claiming it) |

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

## Pre-launch checklist
- [x] Domain bought (Cloudflare, auto-renew on)
- [ ] Domain hardening: transfer lock, DNSSEC, 2FA on Cloudflare
- [ ] Trademark search done (USPTO classes 9, 41); filing considered
- [x] Site live: home, guide pages, Privacy, Support, `llms.txt`, JSON-LD, sitemap
- [x] AI crawlers allowed (`robots.txt`; Cloudflare is DNS only, so its bot rules don't apply)
- [x] App Review login (Jellyfin public demo; replace with your own demo server if it becomes unreliable)
- [x] Beta approved → Public Link on → "Join the beta" button on the site
- [ ] Google Search Console + Bing Webmaster Tools verified, sitemap submitted
- [x] GitHub: homepage → wavetile.com, topics added
- [ ] Re-shoot screenshots (site and App Store) with licensed or public-domain artwork
- [ ] App Store name, subtitle, keywords, screenshots, privacy label
- [x] Repo ready for listing PRs: MPL-2.0 license, README for users (beta link, site, support), topics (2026-10-29)
- [ ] Listing PRs open (jellyfin.org, awesome-jellyfin)
- [ ] Launch posts drafted; press kit up
- [ ] `vercel logout` on this Mac when deploys are done

## Security
- **App Review demo server:** a separate Jellyfin instance with a non-admin, read-only account and only royalty-free/public-domain music. Expect the credentials to leak, and keep it away from your personal server.
- **Screenshots and videos:** no real server addresses, usernames or tokens.
- **Privacy claims** must match the app. "Data Not Collected" is wrong if you add analytics or crash reporting later.
- **Site:** HTTPS only. Use HSTS once it's stable, and set no third-party trackers if you're advertising privacy.
