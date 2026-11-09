---
name: testflight
description: Archive Wavetile and upload the build to TestFlight. Use only when the user asks for a TestFlight build.
disable-model-invocation: true
---

# TestFlight upload

Only when asked. It uploads whatever is checked out, so confirm the work is committed first.

`scripts/testflight.sh` is what the user runs in Terminal. Claude runs its steps directly instead, because the script would run Xcode inside the sandbox. Run these as four separate plain commands, without `$(...)`. `<repo>` is the absolute repo path.

1. `date +%Y%m%d%H%M` → the build number (timestamps, so don't bump `CURRENT_PROJECT_VERSION`)
2. `xcodegen generate --spec <repo>/project.yml --project <repo>`
3. `xcodebuild archive -project <repo>/Wavetile.xcodeproj -scheme Wavetile -configuration Release -destination generic/platform=iOS -archivePath <repo>/build/Wavetile.xcarchive -allowProvisioningUpdates -quiet CURRENT_PROJECT_VERSION=<number> 2>&1`
4. `xcodebuild -exportArchive -archivePath <repo>/build/Wavetile.xcarchive -exportOptionsPlist <repo>/scripts/ExportOptions.plist -exportPath <repo>/build/export -allowProvisioningUpdates 2>&1` (uploads; done at `** EXPORT SUCCEEDED **`)

With `-quiet`, "failed with exit code 0 but produced no further output" lines are noise; real failures show `error:` with a file path or `ARCHIVE FAILED`.

Archive and export are not on the allow list, so each asks for approval.
