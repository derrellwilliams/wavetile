# Wavetile launch & growth plan

The goal: when someone searches or asks an LLM for "a Jellyfin music app for iPhone", Wavetile is in the answer.

## Status (2026-10-28)
| Area | State |
|---|---|
| wavetile.com | Live on Vercel (`site/`, auto-deploys on push), DNS on Cloudflare (DNS only), HTTPS |
| Pages | Home, Why Wavetile, Podcasts with Jellyfin, Getting started, Support, Privacy |
| TestFlight | Build 202610281900 in Beta App Review for the external "public beta" group |
| App Review login | Jellyfin's public demo: `https://demo.jellyfin.org/stable`, user `demo`, blank password (any typed password fails) |
| Contact | realslimscrawny@gmail.com (site, support and privacy pages) |
| Next | Once the beta is approved: enable the Public Link and make the hero button "Join the beta" |

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
| Name | 30 | `Wavetile: Jellyfin Music` |
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
| Pages | Live: Home, Why Wavetile (`/why-wavetile`), Podcasts with Jellyfin (`/jellyfin-podcasts`), Getting started (`/getting-started`), Support, Privacy. Linked from every footer. Later: Changelog, Press |
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
4. **Get listed on third-party sites** (this matters most):
   - jellyfin.org clients page (PR to the jellyfin.org repo)
   - awesome-jellyfin and awesome-selfhosted lists (PRs)
   - Roundup sites: jellywatch.app, appshunter, AlternativeTo (add Wavetile as an alternative to Finamp, etc.)
   - r/jellyfin, r/selfhosted, r/iosapps, the Jellyfin forum
5. **GitHub**: put the positioning line in the repo description, add topics (`jellyfin`, `ios`, `music-player`, `podcast`, `swiftui`, `selfhosted`), and link the App Store and site.
6. **Check it monthly**: ask ChatGPT, Claude, Perplexity and Gemini "best Jellyfin music app for iPhone" and log the results.

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
- [ ] Beta approved → Public Link on → "Join the beta" button on the site
- [ ] Google Search Console + Bing Webmaster Tools verified, sitemap submitted
- [ ] GitHub: homepage → wavetile.com, topics added
- [ ] Re-shoot screenshots (site and App Store) with licensed or public-domain artwork
- [ ] App Store name, subtitle, keywords, screenshots, privacy label
- [ ] Listing PRs open (jellyfin.org, awesome-jellyfin, awesome-selfhosted)
- [ ] Launch posts drafted; press kit up
- [ ] `vercel logout` on this Mac when deploys are done

## Security
- **App Review demo server:** a separate Jellyfin instance with a non-admin, read-only account and only royalty-free/public-domain music. Expect the credentials to leak, and keep it away from your personal server.
- **Screenshots and videos:** no real server addresses, usernames or tokens.
- **Privacy claims** must match the app. "Data Not Collected" is wrong if you add analytics or crash reporting later.
- **Site:** HTTPS only. Use HSTS once it's stable, and set no third-party trackers if you're advertising privacy.
