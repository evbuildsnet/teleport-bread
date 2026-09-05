#!/bin/zsh
# Append a release to the Sparkle appcast. Sparkle signs each archive with the
# private EdDSA key from the login Keychain, or from stdin when
# SPARKLE_PRIVATE_KEY is set (CI). Existing items in the appcast are kept.
#
#   scripts/appcast.sh <archives-dir> <download-url-prefix> <appcast.xml>
set -euo pipefail
archives=$1 prefix=$2 appcast=$3
bin="$("$(dirname "$0")/sparkle-tools.sh")"
args=(--download-url-prefix "$prefix" --link https://teleportbread.com -o "$appcast" "$archives")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "$SPARKLE_PRIVATE_KEY" | "$bin/generate_appcast" --ed-key-file - "${args[@]}"
else
  "$bin/generate_appcast" "${args[@]}"
fi
