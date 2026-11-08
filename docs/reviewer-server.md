# Reviewer server preparation — November 7, 2026

Prepared plan; no server provisioned, credentials generated, media downloaded or account changes made. This supports the reviewer-access gate in [LAUNCH.md](LAUNCH.md). Device acceptance belongs in [testparty.md](testparty.md).

## Deployment requirements

1. Choose a dedicated host or isolated VM/container, separate from the personal Jellyfin server and its storage. Do not mount personal libraries, home directories or backup volumes. Use a dedicated hostname with valid public HTTPS; review must not require a VPN, Tailscale membership, CAPTCHA or Cloudflare Access login.
2. Install a currently supported Jellyfin release using the [official container instructions](https://jellyfin.org/docs/general/installation/container/). At deployment time review [upstream security advisories](https://github.com/jellyfin/jellyfin/security), choose a patched version and record its exact image digest. Do not freeze an unverified version in this preparation document.
3. Persist config/cache separately; mount only the curated demo media read-only. Terminate HTTPS at a reverse proxy and restrict the origin port to that proxy. Allow normal Jellyfin API, streaming and download requests. Keep administrative access separate and restricted.
4. Create a separate admin account and a non-admin reviewer account. Restrict the reviewer to the demo music library. Allow remote login, audio playback, required transcoding and downloads; disable media deletion, administration and remote control of other users. “Read-only” here means no destructive/admin permissions, not a blanket denial of playback/download API requests. Do not promise editable playlist/cover features if permissions prohibit them.
5. Use unique credentials, stored outside the repository and entered directly in App Store Connect. Assume reviewer credentials may become public. Do not use the same credentials anywhere else or expose an admin password.
6. Keep the instance available throughout review and any appeal, with disk/availability checks. Avoid scheduled resets during review. Preserve the tested library and credentials; rotate or retire access after review is finished.

## Demo library requirements

Prepare at least three albums across two artists, with several tracks each, one playlist and artwork. Include a short MP3 album and FLAC or ALAC source material to exercise downloads and format handling. Use consistent titles and artwork suitable for screenshots. Add a continuous two-track sample only if licensing permits splitting/editing it.

Use recordings and artwork you created or have explicit redistribution rights for. A public-domain composition does not establish rights to a particular recording or cover. “Royalty-free” does not automatically permit public demo hosting or marketing screenshots. Verify both the recording and composition, and any territory restrictions; avoid ambiguous rights.

Maintain this inventory before uploading files:

| File / album | Creator | Source URL | Recording/composition license | Artwork license | Required attribution | Permission evidence |
|---|---|---|---|---|---|---|
| Pending selection | | | | | | |

Keep license copies with the server's records; record attribution in the library or accompanying credits as required. Do not use personal listening history, personal artwork, real usernames or server addresses in screenshots.

## Engineering acceptance and handoff

- Confirm public HTTPS and certificate renewal, origin isolation, non-admin permissions, demo-only mounts and sufficient storage for transcoding.
- Confirm the selected server's security fixes and log the version/image digest. Avoid logging Authorization headers, passwords or session-token query parameters.
- Prepare exact sign-in steps and named sample albums for [app-review-notes.md](app-review-notes.md). Keep credentials in App Store Connect, not this document.
- Hand the URL and account to the user for the existing fresh-install login/playback checks in testparty. Investigate failures before submission.
- Record host, owner, version, library/license inventory, availability period and completed testparty result in the release record. Do not mark reviewer access complete based on this plan alone.
