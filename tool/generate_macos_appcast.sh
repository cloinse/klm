#!/usr/bin/env bash

set -euo pipefail

KLM_SPARKLE_VERSION="2.9.2"
KLM_SPARKLE_ARCHIVE_SHA256="1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95"
KLM_ARCHIVES_DIRECTORY="${1:?Pass the directory containing the update DMG}"
KLM_APPCAST_PATH="${2:?Pass the output appcast path}"
KLM_DOWNLOAD_URL_PREFIX="${KLM_UPDATE_DOWNLOAD_URL_PREFIX:?Set KLM_UPDATE_DOWNLOAD_URL_PREFIX}"
KLM_DOWNLOAD_URL_PREFIX="${KLM_DOWNLOAD_URL_PREFIX%/}/"
KLM_RELEASE_NOTES_PATH="${KLM_RELEASE_NOTES_PATH:-}"

test -d "$KLM_ARCHIVES_DIRECTORY"
/bin/mkdir -p "$(/usr/bin/dirname "$KLM_APPCAST_PATH")"

KLM_SPARKLE_ROOT="$(/usr/bin/mktemp -d /tmp/klm-sparkle-tools.XXXXXX)"
cleanup() {
  case "$KLM_SPARKLE_ROOT" in
    /tmp/klm-sparkle-tools.*|/private/tmp/klm-sparkle-tools.*)
      /bin/rm -rf "$KLM_SPARKLE_ROOT"
      ;;
    *) return 1 ;;
  esac
}
trap cleanup EXIT

KLM_SPARKLE_ARCHIVE="$KLM_SPARKLE_ROOT/Sparkle.tar.xz"
/usr/bin/curl -fL \
  "https://github.com/sparkle-project/Sparkle/releases/download/${KLM_SPARKLE_VERSION}/Sparkle-${KLM_SPARKLE_VERSION}.tar.xz" \
  -o "$KLM_SPARKLE_ARCHIVE"

KLM_DOWNLOADED_SHA256="$(/usr/bin/shasum -a 256 "$KLM_SPARKLE_ARCHIVE" | /usr/bin/awk '{ print $1 }')"
test "$KLM_DOWNLOADED_SHA256" = "$KLM_SPARKLE_ARCHIVE_SHA256"
/usr/bin/tar -xf "$KLM_SPARKLE_ARCHIVE" -C "$KLM_SPARKLE_ROOT"

generate_appcast() {
  "$KLM_SPARKLE_ROOT/bin/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "$KLM_DOWNLOAD_URL_PREFIX" \
    --maximum-deltas 0 \
    -o "$KLM_APPCAST_PATH" \
    "$KLM_ARCHIVES_DIRECTORY"
}

verify_appcast() {
  "$KLM_SPARKLE_ROOT/bin/sign_update" \
    --verify \
    --ed-key-file - \
    "$KLM_APPCAST_PATH"
}

embed_release_notes() {
  test -z "$KLM_RELEASE_NOTES_PATH" && return 0
  test -f "$KLM_RELEASE_NOTES_PATH"
  ! /usr/bin/grep -Fq ']]>' "$KLM_RELEASE_NOTES_PATH"

  KLM_APPCAST_WITH_NOTES="$KLM_APPCAST_PATH.with-notes"
  /usr/bin/awk -v notes_path="$KLM_RELEASE_NOTES_PATH" '
    !inserted && /<enclosure[ >]/ {
      print "<description sparkle:format=\"plain-text\"><![CDATA["
      while ((getline line < notes_path) > 0) print line
      close(notes_path)
      print "]]></description>"
      inserted = 1
    }
    { print }
  ' "$KLM_APPCAST_PATH" > "$KLM_APPCAST_WITH_NOTES"
  /bin/mv "$KLM_APPCAST_WITH_NOTES" "$KLM_APPCAST_PATH"
}

if test -n "${KLM_SPARKLE_PRIVATE_KEY:-}"; then
  /usr/bin/printf '%s' "$KLM_SPARKLE_PRIVATE_KEY" | generate_appcast
else
  KLM_PRIVATE_KEY_FILE="${KLM_SPARKLE_PRIVATE_KEY_FILE:-.secrets/KLM_SPARKLE_PRIVATE_KEY}"
  test -s "$KLM_PRIVATE_KEY_FILE"
  /bin/cat "$KLM_PRIVATE_KEY_FILE" | generate_appcast
fi

embed_release_notes

if test -n "${KLM_SPARKLE_PRIVATE_KEY:-}"; then
  /usr/bin/printf '%s' "$KLM_SPARKLE_PRIVATE_KEY" | verify_appcast
else
  /bin/cat "$KLM_PRIVATE_KEY_FILE" | verify_appcast
fi

/usr/bin/printf 'Created signed appcast %s\n' "$KLM_APPCAST_PATH"
