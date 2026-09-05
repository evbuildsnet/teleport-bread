#!/bin/zsh
# Prints the path to Sparkle's CLI tools (generate_appcast, sign_update,
# generate_keys), downloading the pinned release on first use. Homebrew's
# cask is unreliable, and the official tarball is what CI uses anyway.
set -euo pipefail
version=2.9.6
sha256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
dir="${TMPDIR:-/tmp}/sparkle-tools-$version"
if [[ ! -x "$dir/bin/generate_appcast" ]]; then
  tarball="$(mktemp)"
  curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$tarball"
  echo "$sha256  $tarball" | shasum -a 256 -c - >/dev/null
  mkdir -p "$dir" && tar -xJf "$tarball" -C "$dir"
  rm -f "$tarball"
fi
echo "$dir/bin"
