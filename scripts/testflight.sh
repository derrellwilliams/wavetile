#!/bin/zsh
# Archives Wavetile and uploads it to App Store Connect for TestFlight.
#
# One-time setup:
#   1. Xcode > Settings > Accounts: sign in with your Apple Developer account.
#   2. Set DEVELOPMENT_TEAM in project.yml to your Team ID.
#   3. Create the app in App Store Connect (bundle ID com.derrellwilliams.wavetile).
#
# Each upload needs a new build number: pass one, or it uses the current time.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${1:-$(date +%Y%m%d%H%M)}"
ARCHIVE="build/Wavetile.xcarchive"

xcodegen generate
xcodebuild archive \
  -project Wavetile.xcodeproj -scheme Wavetile -configuration Release \
  -destination generic/platform=iOS -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates

echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect > TestFlight after processing (~10-30 min)."
