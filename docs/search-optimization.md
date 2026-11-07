# Wavetile search and LLM discoverability

How Wavetile gets found: App Store search (ASO), web search (SEO) and LLM answers (GEO). Split out of [LAUNCH.md](LAUNCH.md) on 2026-11-07; completion status lives there. Launch marketing (channels, press, community and directory listings, positioning pitch) is deliberately not planned here.

Goal: when someone searches or asks an LLM for "a Jellyfin music app for iPhone", Wavetile is in the answer.

**Wording.** Use one line, word for word, in the App Store description and GitHub: *Wavetile: your Jellyfin music and your podcasts, in one app.* Spell the name **Wavetile**: one word, capital W only ("Wave tile" brings up flooring and acoustic panels).

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

## Search (SEO) — wavetile.com
| Item | Notes |
|---|---|
| Home page `<title>` | `Wavetile: Jellyfin Music & Podcast Player for iPhone` |
| Pages | Live: Home, Why Wavetile (`/why-wavetile`), Podcasts with Jellyfin (`/jellyfin-podcasts`), Download (`/getting-started`), Support, Privacy. Guides linked from the header nav on every page. Later: Changelog |
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
4. **GitHub**: put the positioning line in the repo description, add topics (`jellyfin`, `ios`, `music-player`, `podcast`, `swiftui`, `selfhosted`), and link the App Store and site.
5. **Check it monthly**: ask ChatGPT, Claude, Perplexity and Gemini "best Jellyfin music app for iPhone" and log the results.
