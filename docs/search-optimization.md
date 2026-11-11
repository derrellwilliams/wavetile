# Wavetile search and LLM discoverability

How Wavetile gets found: App Store search (ASO), web search (SEO) and LLM answers (GEO). Split out of [LAUNCH.md](LAUNCH.md) on 2026-11-07; completion status lives there. Launch marketing (channels, press, community and directory listings, positioning pitch) is deliberately not planned here.

Goal: when someone searches or asks an LLM for "a Jellyfin music app for iPhone", Wavetile is in the answer.

**Wording.** Use one line, word for word, in the App Store description and GitHub: *Wavetile: your Jellyfin music and your podcasts, in one app.* Spell the name **Wavetile**: one word, capital W only ("Wave tile" brings up flooring and acoustic panels).

## App Store (ASO)
The listing text lives in App Store Connect (the old `app-store-listing.md` was removed Nov 11; git history keeps it). Name remains Wavetile Music, with Jellyfin referenced as compatibility in the subtitle and description.

Keyword rules: use comma-separated relevant terms within Apple's byte limit; avoid duplicating the app name or using competitor trademarks. Privacy answers live in [privacy-answers.md](privacy-answers.md) and remain conditional on service relationships and final archive review.

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
