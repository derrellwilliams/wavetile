---
name: testflight
description: Archive Wavetile and upload the build to TestFlight. Use only when the user asks for a TestFlight build.
disable-model-invocation: true
---

# TestFlight upload

Only when asked. It uploads whatever is checked out, so confirm the work is committed first.

## Before archiving

Run as separate plain commands; stop and report if any fails.

1. `git status --porcelain --untracked-files=no` is empty, and the branch is `main` (the work lands on `main`).
2. `scripts/design-system.py --check` exits 0 (the gallery isn't stale).
3. Package tests pass (`WavetileKit-Package`, ~30 s; see CLAUDE.md "Build & run"). UI tests only if the user asks (~5 min).
4. Note `git rev-parse --short HEAD` and the changes since the last upload: read the newest row in `docs/LAUNCH.md` for the previous build's hash, then `git log --oneline <that-hash>..HEAD`.

`scripts/testflight.sh` is what the user runs in Terminal. Claude runs its steps directly instead, because the script would run Xcode inside the sandbox. Run these as four separate plain commands, without `$(...)`. `<repo>` is the absolute repo path.

1. `date +%Y%m%d%H%M` → the build number (timestamps, so don't bump `CURRENT_PROJECT_VERSION`)
2. `xcodegen generate --spec <repo>/project.yml --project <repo>`
3. `xcodebuild archive -project <repo>/Wavetile.xcodeproj -scheme Wavetile -configuration Release -destination generic/platform=iOS -archivePath <repo>/build/Wavetile.xcarchive -allowProvisioningUpdates -quiet CURRENT_PROJECT_VERSION=<number> 2>&1`
4. `xcodebuild -exportArchive -archivePath <repo>/build/Wavetile.xcarchive -exportOptionsPlist <repo>/scripts/ExportOptions.plist -exportPath <repo>/build/export -allowProvisioningUpdates 2>&1` (uploads; done at `** EXPORT SUCCEEDED **`)

With `-quiet`, "failed with exit code 0 but produced no further output" lines are noise; real failures show `error:` with a file path or `ARCHIVE FAILED`.

Archive and export are not on the allow list, so each asks for approval.

## After the upload

Once `** EXPORT SUCCEEDED **` shows, record it (the "Docs: … uploaded to TestFlight" step). Edit the files; don't commit unless the user asks.

1. `docs/LAUNCH.md`, the release table row for the current version (`CFBundleShortVersionString`/`MARKETING_VERSION` in `project.yml`): add one sentence in the existing style: `Nov DD: build <number> (<short-hash>) replaces it: <what changed, user-visible>`. If the version train is new (the last one was approved), add a row instead. Keep what's already there; don't rewrite earlier builds.
2. Same row: end with the device check to run before submitting (what to verify on TestFlight), if the changes need one.
3. `docs/qa-evidence.md`: add a dated section only if a regression or UI run happened this session; copy the heading style (`## <Topic> — <Month D>, <year>`) and the result counts from the run.
4. `CLAUDE.md`: only if behavior it documents changed (the "Release planning" paragraph rarely needs a touch). Don't add release-log lines.
5. Tell the user the build number, the hash, that processing takes ~10–30 min, and that the docs are edited but uncommitted. Suggested commit subject: `Docs: <version> (build <number>) uploaded to TestFlight <Mon D>`.

Dates are today's date as the user's machine reports it (`date +%b\ %-d`), never guessed.
