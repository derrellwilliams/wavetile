# wavetile.com

The marketing site: static HTML/CSS/JS with no build step. Colors, fonts and icons come from the app's `DesignSystem` package.

## Deploy (Vercel)
1. In Vercel, choose **Add New → Project**, import `derrellwilliams/wavetile`, and set **Root Directory** to `site`.
2. Set Framework Preset to **Other**. Leave the build and output settings empty.
3. In Domains, add `wavetile.com` and `www.wavetile.com`, with www redirecting to the apex.
4. In Cloudflare DNS, add the records Vercel shows, set to **DNS only** (gray cloud). Vercel issues the TLS certificate itself.

Commits that don't touch `site/` skip the deploy (`ignoreCommand` in `vercel.json`).

## Preview locally
```sh
python3 -m http.server -d site 8080   # then open http://localhost:8080
```
Clean URLs (`/privacy`) only work on Vercel. Locally, use `/privacy.html`.

## At launch
- `index.html`: uncomment the `apple-itunes-app` meta tag (Smart App Banner) and swap the "Coming soon" badge for Apple's official App Store badge, linked to the listing.
- Replace the `.qr` placeholder with an SVG QR code for the App Store URL.
- Add `"offers": { "@type": "Offer", "price": "0", "priceCurrency": "USD" }` and `downloadUrl` to the `MobileApplication` JSON-LD.
- Update `lastmod` in `sitemap.xml` whenever a page changes.

## Screenshots
`assets/screens/*.webp` are 924×2000 phone captures. Before launch, replace these with captures from a demo library with licensed or public-domain artwork (see `docs/LAUNCH.md`).
