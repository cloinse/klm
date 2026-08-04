#!/usr/bin/env bash

set -euo pipefail

KLM_APP_NAME="${KLM_APP_NAME:-Kontakt Library Manager}"
KLM_APP_PATH="${1:-build/macos/Build/Products/Release/${KLM_APP_NAME}.app}"
KLM_DMG_PATH="${2:-build/distribution/Kontakt-Library-Manager.dmg}"
KLM_TOOL_DIRECTORY="$(CDPATH= cd -- "$(/usr/bin/dirname "$0")" && /bin/pwd)"

test -d "$KLM_APP_PATH"
"$KLM_TOOL_DIRECTORY/prepare_adhoc_sparkle.sh" "$KLM_APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$KLM_APP_PATH"

KLM_DMG_PARENT="$(/usr/bin/dirname "$KLM_DMG_PATH")"
/bin/mkdir -p "$KLM_DMG_PARENT"

KLM_DMG_ROOT="$(/usr/bin/mktemp -d /tmp/klm-dmg.XXXXXX)"
KLM_DMG_SOURCE="$KLM_DMG_ROOT/source"
KLM_READ_WRITE_DMG="$KLM_DMG_ROOT/Kontakt-Library-Manager-rw.dmg"
KLM_TEMP_DMG="$KLM_DMG_ROOT/Kontakt-Library-Manager.dmg"
KLM_ATTACH_PLIST="$KLM_DMG_ROOT/attach.plist"
KLM_MOUNT_POINT=""
KLM_SWIFT_CACHE="$KLM_DMG_ROOT/swift-module-cache"
KLM_ATTACHED=false
KLM_DEVICE=""

cleanup() {
  if test "$KLM_ATTACHED" = true; then
    if test -n "$KLM_MOUNT_POINT"; then
      /usr/bin/hdiutil detach "$KLM_MOUNT_POINT" -force >/dev/null 2>&1 || true
    elif test -n "$KLM_DEVICE"; then
      /usr/bin/hdiutil detach "$KLM_DEVICE" -force >/dev/null 2>&1 || true
    fi
  fi
  case "$KLM_DMG_ROOT" in
    /tmp/klm-dmg.*|/private/tmp/klm-dmg.*) /bin/rm -rf "$KLM_DMG_ROOT" ;;
    *) return 1 ;;
  esac
}
trap cleanup EXIT

/bin/mkdir -p "$KLM_DMG_SOURCE" "$KLM_SWIFT_CACHE"
/usr/bin/ditto "$KLM_APP_PATH" "$KLM_DMG_SOURCE/${KLM_APP_NAME}.app"

KLM_APP_KILOBYTES="$(/usr/bin/du -sk "$KLM_APP_PATH" | /usr/bin/awk '{ print $1 }')"
KLM_IMAGE_KILOBYTES="$((KLM_APP_KILOBYTES + 32768))"
/usr/bin/hdiutil create \
  -volname "$KLM_APP_NAME" \
  -srcfolder "$KLM_DMG_SOURCE" \
  -fs HFS+ \
  -format UDRW \
  -size "${KLM_IMAGE_KILOBYTES}k" \
  "$KLM_READ_WRITE_DMG"

/usr/bin/hdiutil attach \
  -nobrowse \
  -noverify \
  -plist \
  "$KLM_READ_WRITE_DMG" > "$KLM_ATTACH_PLIST"
KLM_ATTACHED=true
for KLM_ENTITY_INDEX in 0 1 2 3 4 5; do
  KLM_ENTITY_DEVICE="$(/usr/libexec/PlistBuddy -c \
    "Print :system-entities:${KLM_ENTITY_INDEX}:dev-entry" \
    "$KLM_ATTACH_PLIST" 2>/dev/null || true)"
  if test -n "$KLM_ENTITY_DEVICE"; then
    KLM_DEVICE="$KLM_ENTITY_DEVICE"
  fi
  KLM_ENTITY_MOUNT_POINT="$(/usr/libexec/PlistBuddy -c \
    "Print :system-entities:${KLM_ENTITY_INDEX}:mount-point" \
    "$KLM_ATTACH_PLIST" 2>/dev/null || true)"
  if test -n "$KLM_ENTITY_MOUNT_POINT" && test -d "$KLM_ENTITY_MOUNT_POINT"; then
    KLM_MOUNT_POINT="$KLM_ENTITY_MOUNT_POINT"
    break
  fi
done
test -d "$KLM_MOUNT_POINT"

KLM_BACKGROUND_DIRECTORY="$KLM_MOUNT_POINT/.background"
/bin/ln -s /Applications "$KLM_MOUNT_POINT/Applications"
/bin/mkdir -p "$KLM_BACKGROUND_DIRECTORY"
CLANG_MODULE_CACHE_PATH="$KLM_SWIFT_CACHE" /usr/bin/xcrun swift \
  "$KLM_TOOL_DIRECTORY/create_dmg_background.swift" \
  "$KLM_BACKGROUND_DIRECTORY/background.png"
/usr/bin/touch "$KLM_MOUNT_POINT/.metadata_never_index"
/usr/bin/osascript \
  "$KLM_TOOL_DIRECTORY/configure_dmg.applescript" \
  "$KLM_APP_NAME" \
  "$KLM_APP_NAME"
/bin/sync
test -s "$KLM_MOUNT_POINT/.DS_Store"
/usr/bin/hdiutil detach "$KLM_MOUNT_POINT"
KLM_ATTACHED=false

/usr/bin/hdiutil convert \
  "$KLM_READ_WRITE_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$KLM_TEMP_DMG"
/usr/bin/hdiutil verify "$KLM_TEMP_DMG"
/bin/mv -f "$KLM_TEMP_DMG" "$KLM_DMG_PATH"
/usr/bin/shasum -a 256 "$KLM_DMG_PATH" > "$KLM_DMG_PATH.sha256"
/usr/bin/printf 'Created %s\n' "$KLM_DMG_PATH"
