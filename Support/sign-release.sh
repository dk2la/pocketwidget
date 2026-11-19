#!/bin/bash
# Signs a built Pocket.app for release, inside out.
#
# Xcode signs the app and the Sparkle framework, but leaves the helper
# programs inside the framework with the ad-hoc signature they were built
# with. Apple's notarization rejects those, so each helper is signed again
# with the Developer ID, then the framework and the app that contain them.
#
# Usage: Support/sign-release.sh <path to Pocket.app> [identity]
set -euo pipefail

app=${1:?usage: Support/sign-release.sh <path to Pocket.app> [identity]}
identity=${2:-Developer ID Application}
entitlements="$(cd "$(dirname "$0")" && pwd)/Pocket.entitlements"
sparkle="$app/Contents/Frameworks/Sparkle.framework"

sign() {
  codesign --force --sign "$identity" --options runtime --timestamp "$@"
}

sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
# The downloader ships with its own entitlements; keep them.
sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
sign "$sparkle/Versions/B/Autoupdate"
sign "$sparkle/Versions/B/Updater.app"
sign "$sparkle"
sign --entitlements "$entitlements" "$app"

codesign --verify --deep --strict "$app"
# Every program in the bundle must carry the Developer ID, not an ad-hoc
# signature.
while IFS= read -r -d '' file; do
  if file -b "$file" | grep -q "Mach-O" && codesign -dv "$file" 2>&1 | grep -q "Signature=adhoc"; then
    echo "error: $file is still signed ad-hoc" >&2
    exit 1
  fi
done < <(find "$app" -type f -perm +111 -print0)
echo "Signed $app"
