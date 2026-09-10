#!/bin/zsh
# Build the direct-download Mac app: archive with Developer ID, notarize,
# staple, zip. Output: <out>/TeleportBread-<version>.zip
#
#   scripts/release-direct.sh <version> <build> <out-dir>
#
# Notarization reads NOTARY_KEY_ID, NOTARY_ISSUER_ID and NOTARY_KEY_PATH
# (an App Store Connect API key). Set SKIP_NOTARIZE=1 to rehearse locally.
set -euo pipefail
version=$1 build=$2 out=$3
root="$(cd "$(dirname "$0")/.." && pwd)"
archive="$out/TeleportBread.xcarchive"
export_dir="$out/export"
app="$export_dir/TeleportBread.app"
zip="$out/TeleportBread-$version.zip"

mkdir -p "$out"
(cd "$root/app" && xcodegen generate -q)
xcodebuild -project "$root/app/TeleportBread.xcodeproj" -scheme TeleportBreadMacDirect \
  -configuration Release -destination "platform=macOS,arch=arm64" \
  -archivePath "$archive" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  -quiet archive
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist "$root/app/ExportOptions-DeveloperID.plist" -quiet

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]]; then
  ditto -c -k --keepParent "$app" "$out/notarize.zip"
  xcrun notarytool submit "$out/notarize.zip" --wait \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  xcrun stapler staple "$app"
  rm -f "$out/notarize.zip"
fi

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "$zip"
