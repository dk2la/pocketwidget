#!/bin/bash
# Builds the DMG a buyer downloads: Pocket and a shortcut to Applications on
# a background that says to drag one onto the other.
#
#     Support/make-dmg.sh <Pocket.app> <output.dmg>
#
# Needs dmgbuild (`pip install dmgbuild`); set DMGBUILD to its path when it
# is not on PATH. The layout is in Support/dmg/settings.py.
set -euo pipefail

app=${1:?usage: make-dmg.sh <Pocket.app> <output.dmg>}
output=${2:?usage: make-dmg.sh <Pocket.app> <output.dmg>}
here=$(cd "$(dirname "$0")" && pwd)

[[ -f "$app/Contents/Resources/AppIcon.icns" ]] \
  || { echo "error: $app has no AppIcon.icns" >&2; exit 1; }

rm -f "$output"
"${DMGBUILD:-dmgbuild}" -s "$here/dmg/settings.py" -D app="$app" -D art="$here/dmg" Pocket "$output"
