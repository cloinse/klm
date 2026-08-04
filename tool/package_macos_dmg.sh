#!/usr/bin/env bash

set -euo pipefail

KLM_APP_NAME="${KLM_APP_NAME:-Kontakt Library Manager}"
KLM_APP_PATH="${1:-build/macos/Build/Products/Release/${KLM_APP_NAME}.app}"
KLM_DMG_PATH="${2:-build/distribution/Kontakt-Library-Manager.dmg}"
KLM_TOOL_DIRECTORY="$(CDPATH= cd -- "$(/usr/bin/dirname "$0")" && /bin/pwd)"

test -d "$KLM_APP_PATH"
KLM_APP_PARENT="$(CDPATH= cd -- "$(/usr/bin/dirname "$KLM_APP_PATH")" && /bin/pwd)"
KLM_APP_PATH="$KLM_APP_PARENT/$(/usr/bin/basename "$KLM_APP_PATH")"
if test "${KLM_PREPARE_APP:-true}" = true; then
  "$KLM_TOOL_DIRECTORY/prepare_adhoc_sparkle.sh" "$KLM_APP_PATH"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$KLM_APP_PATH"

KLM_DMG_PARENT="$(/usr/bin/dirname "$KLM_DMG_PATH")"
/bin/mkdir -p "$KLM_DMG_PARENT"

KLM_DMG_ROOT="$(/usr/bin/mktemp -d /tmp/klm-dmg.XXXXXX)"
KLM_TEMP_DMG="$KLM_DMG_ROOT/Kontakt-Library-Manager.dmg"
KLM_BACKGROUND="$KLM_DMG_ROOT/background.png"
KLM_SWIFT_CACHE="$KLM_DMG_ROOT/swift-module-cache"
KLM_DMGBUILD_VENV="$KLM_DMG_ROOT/dmgbuild-venv"
KLM_PYTHON="${KLM_DMGBUILD_PYTHON:-$(command -v python3)}"

cleanup() {
  case "$KLM_DMG_ROOT" in
    /tmp/klm-dmg.*|/private/tmp/klm-dmg.*) /bin/rm -rf "$KLM_DMG_ROOT" ;;
    *) return 1 ;;
  esac
}
trap cleanup EXIT

/bin/mkdir -p "$KLM_SWIFT_CACHE"
CLANG_MODULE_CACHE_PATH="$KLM_SWIFT_CACHE" /usr/bin/xcrun swift \
  "$KLM_TOOL_DIRECTORY/create_dmg_background.swift" \
  "$KLM_BACKGROUND"

"$KLM_PYTHON" -c \
  'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'
"$KLM_PYTHON" -m venv "$KLM_DMGBUILD_VENV"
"$KLM_DMGBUILD_VENV/bin/python3" -m pip install \
  --disable-pip-version-check \
  --no-deps \
  --no-compile \
  --require-hashes \
  -r "$KLM_TOOL_DIRECTORY/dmgbuild-requirements.txt"

"$KLM_DMGBUILD_VENV/bin/dmgbuild" \
  -s "$KLM_TOOL_DIRECTORY/dmg_settings.py" \
  -D "app=$KLM_APP_PATH" \
  -D "background=$KLM_BACKGROUND" \
  "$KLM_APP_NAME" \
  "$KLM_TEMP_DMG"

/usr/bin/hdiutil verify "$KLM_TEMP_DMG"
/bin/mv -f "$KLM_TEMP_DMG" "$KLM_DMG_PATH"
/usr/bin/shasum -a 256 "$KLM_DMG_PATH" > "$KLM_DMG_PATH.sha256"
/usr/bin/printf 'Created %s\n' "$KLM_DMG_PATH"
