# Secret scanning

Install Gitleaks (`brew install gitleaks`) and enable the tracked hooks in each clone:

```sh
git config core.hooksPath .githooks
```

The commit hook scans staged changes. The push hook scans only the commits being
pushed; GitHub Actions scans all history. Output is redacted. CI uses a version and checksum
pinned Gitleaks binary, read-only permissions, and no saved checkout credentials.
No app runtime dependencies or appearance changes are required.

Run manually: `gitleaks git --redact --no-banner --log-opts="--all" .`.
Treat a new finding as potentially compromised; revoke a live secret before
considering history cleanup. Do not add broad file or key-pattern exceptions.
Template files ending in `.example`, `.sample` or `.template` are the only
allowed exception for secret-file names (see `.gitleaks.toml`). Hooks are opt-in
per clone and `--no-verify` skips them, so the GitHub Actions scan is the backstop.
