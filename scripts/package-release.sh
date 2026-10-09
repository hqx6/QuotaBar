#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-app.sh
ARCH="$(uname -m)"
if [[ "${QUOTABAR_UNIVERSAL:-0}" == "1" ]]; then ARCH="universal"; fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/QuotaBar.app/Contents/Info.plist)"
ARCHIVE="$PWD/dist/QuotaBar-$VERSION-macOS-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent dist/QuotaBar.app "$ARCHIVE"
(cd dist && shasum -a 256 "${ARCHIVE:t}" > "${ARCHIVE:t}.sha256")
print "Release archive: $ARCHIVE"
