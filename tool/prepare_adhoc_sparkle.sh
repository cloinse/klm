#!/usr/bin/env bash

set -euo pipefail

KLM_APP_NAME="${KLM_APP_NAME:-Kontakt Library Manager}"
KLM_APP_PATH="${1:-build/macos/Build/Products/Release/${KLM_APP_NAME}.app}"
KLM_SPARKLE_FRAMEWORK="$KLM_APP_PATH/Contents/Frameworks/Sparkle.framework"
KLM_SPARKLE_VERSION_DIRECTORY="$KLM_SPARKLE_FRAMEWORK/Versions/B"
KLM_KONTAKT_HELPER="$KLM_APP_PATH/Contents/Resources/KontaktLibraryHelper"

test -d "$KLM_APP_PATH"
test -d "$KLM_SPARKLE_FRAMEWORK"
test -x "$KLM_SPARKLE_VERSION_DIRECTORY/Autoupdate"
test -d "$KLM_SPARKLE_VERSION_DIRECTORY/Updater.app"
test -x "$KLM_KONTAKT_HELPER"

# KLM is not sandboxed. These on-demand services are unnecessary and removing
# them keeps the updater free of extra service bundles.
if test -e "$KLM_SPARKLE_VERSION_DIRECTORY/XPCServices"; then
  /bin/rm -rf "$KLM_SPARKLE_VERSION_DIRECTORY/XPCServices"
fi
if test -L "$KLM_SPARKLE_FRAMEWORK/XPCServices"; then
  /bin/rm "$KLM_SPARKLE_FRAMEWORK/XPCServices"
fi

/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
  "$KLM_SPARKLE_VERSION_DIRECTORY/Autoupdate"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
  "$KLM_SPARKLE_VERSION_DIRECTORY/Updater.app"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
  "$KLM_SPARKLE_FRAMEWORK"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
  "$KLM_KONTAKT_HELPER"
/usr/bin/codesign --force --sign - --timestamp=none \
  --entitlements macos/Runner/Release.entitlements \
  "$KLM_APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$KLM_APP_PATH"

KLM_APP_SIGNATURE="$(/usr/bin/codesign -dvvv "$KLM_APP_PATH" 2>&1)"
KLM_HELPER_SIGNATURE="$(/usr/bin/codesign -dvvv "$KLM_KONTAKT_HELPER" 2>&1)"
case "$KLM_APP_SIGNATURE" in
  *'runtime'*)
    /usr/bin/printf '%s\n' \
      'Runner must not enable Hardened Runtime with an ad-hoc Sparkle build.' >&2
    exit 1
    ;;
esac
case "$KLM_HELPER_SIGNATURE" in
  *'runtime'*) ;;
  *)
    /usr/bin/printf '%s\n' \
      'KontaktLibraryHelper must retain Hardened Runtime.' >&2
    exit 1
    ;;
esac
