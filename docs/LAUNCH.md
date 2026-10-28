# Wavetile launch & growth plan

The goal: when someone searches or asks an LLM for "a Jellyfin music app for iPhone", Wavetile is in the answer.

## Positioning
Use one line, word for word, everywhere (App Store, site, GitHub, posts):

> **Wavetile is a native Jellyfin music and podcast player for iPhone.**

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
| Pages | Home, Features, FAQ, Compare, Privacy, Support, Changelog |
| Structured data | `SoftwareApplication` JSON-LD (name, OS, category, price, App Store URL, rating when available) + `FAQPage` |
| Smart App Banner | `<meta name="apple-itunes-app" content="app-id=…">` |
| Compare page | Honest table: Wavetile vs Finamp, Jellify, AmpFin, Manet, Finer Player. "Best X" and "X vs Y" searches land here |
| Changelog | Every release on its own dated page. Fresh content for crawlers |
| Search consoles | Submit the sitemap to Google Search Console and Bing Webmaster Tools (Bing also feeds ChatGPT search and Copilot) |

## LLM visibility (GEO)
LLMs recommend what is written about consistently in many places they trust.

1. **Don't block AI crawlers.** Cloudflare can block AI bots (AI Crawl Control / managed robots.txt). Allow GPTBot, OAI-SearchBot, ClaudeBot, PerplexityBot and Google-Extended on wavetile.com.
2. **`/llms.txt`**: a plain-text summary of what Wavetile is, who it's for, its features, the App Store link and FAQs.
3. **Write FAQ answers the way people ask**: "What's the best Jellyfin music app for iPhone?", "Does Wavetile work offline?", "Does it support podcasts / CarPlay / FLAC?". Answer in the first sentence.
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
| TestFlight beta (r/jellyfin, r/selfhosted) | 2–4 weeks before | Recruit testers, collect quotes, fix bugs |
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
- [ ] Domain: auto-renew on, transfer lock on, DNSSEC on, 2FA on Cloudflare
- [ ] Trademark search done (USPTO classes 9, 41); filing considered
- [ ] App Store name, subtitle, keywords, screenshots, privacy label
- [ ] Demo server for App Review (see Security)
- [ ] Site live: landing page, FAQ, Compare, Privacy, Support, `llms.txt`, JSON-LD, sitemap
- [ ] AI crawlers allowed in Cloudflare
- [ ] Listing PRs open (jellyfin.org, awesome-jellyfin, awesome-selfhosted)
- [ ] Launch posts drafted; press kit up

## Security
- **App Review demo server:** a separate Jellyfin instance with a non-admin, read-only account and only royalty-free/public-domain music. Expect the credentials to leak, and keep it away from your personal server.
- **Screenshots and videos:** no real server addresses, usernames or tokens.
- **Privacy claims** must match the app. "Data Not Collected" is wrong if you add analytics or crash reporting later.
- **Site:** HTTPS only. Use HSTS once it's stable, and set no third-party trackers if you're advertising privacy.
