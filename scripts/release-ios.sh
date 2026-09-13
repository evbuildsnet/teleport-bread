#!/bin/zsh
# Archive the iOS app for App Store Connect and upload it to TestFlight.
#
#   scripts/release-ios.sh <version> <build> <out-dir>
#
# Signing is manual: the "Apple Distribution" certificate must be in the
# keychain, and the "TeleportBread iOS App Store" profile is downloaded from
# App Store Connect on demand using the API key in ASC_KEY_ID, ASC_ISSUER_ID
# and ASC_KEY_PATH. The same key uploads the build. SKIP_UPLOAD=1 only archives.
set -euo pipefail
version=$1 build=$2 out=$3
root="$(cd "$(dirname "$0")/.." && pwd)"
archive="$out/TeleportBread-iOS.xcarchive"
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

mkdir -p "$out"
(cd "$root/app" && xcodegen generate -q)
xcodebuild -project "$root/app/TeleportBread.xcodeproj" -scheme TeleportBread \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$archive" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="TeleportBread iOS App Store" \
  "${auth[@]}" -quiet archive

if [[ "${SKIP_UPLOAD:-0}" != 1 ]]; then
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export-ios" \
    -exportOptionsPlist "$root/app/ExportOptions-AppStore.plist" "${auth[@]}" -quiet
fi
echo "$archive"
