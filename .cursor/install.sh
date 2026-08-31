#!/usr/bin/env bash
# Cloud Agent bootstrap for Kontakt Library Manager.
#
# Installs the pinned Flutter SDK (matching the Codemagic/GitHub CI toolchain)
# and refreshes Dart/Flutter package dependencies. The script is idempotent: it
# skips the SDK download when a matching Flutter is already present (for example
# when booting from an environment snapshot that already contains it).
set -euo pipefail

KLM_FLUTTER_VERSION="3.38.9"
KLM_FLUTTER_ROOT="/opt/flutter"
KLM_FLUTTER_ARCHIVE="flutter_linux_${KLM_FLUTTER_VERSION}-stable.tar.xz"
KLM_FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${KLM_FLUTTER_ARCHIVE}"

log() { printf '[klm-install] %s\n' "$1"; }

install_flutter() {
  if [ -x "${KLM_FLUTTER_ROOT}/bin/flutter" ] \
    && "${KLM_FLUTTER_ROOT}/bin/flutter" --version 2>/dev/null \
      | grep -q "Flutter ${KLM_FLUTTER_VERSION}"; then
    log "Flutter ${KLM_FLUTTER_VERSION} already present at ${KLM_FLUTTER_ROOT}."
    return
  fi

  log "Installing Flutter ${KLM_FLUTTER_VERSION} to ${KLM_FLUTTER_ROOT}."
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "${KLM_FLUTTER_URL}" -o "${tmp}/${KLM_FLUTTER_ARCHIVE}"
  sudo rm -rf "${KLM_FLUTTER_ROOT}"
  sudo mkdir -p "$(dirname "${KLM_FLUTTER_ROOT}")"
  sudo tar -xf "${tmp}/${KLM_FLUTTER_ARCHIVE}" -C "$(dirname "${KLM_FLUTTER_ROOT}")"
  sudo chown -R "$(id -u):$(id -g)" "${KLM_FLUTTER_ROOT}"
  rm -rf "${tmp}"
}

ensure_path() {
  # Make Flutter discoverable in this script and in future interactive shells.
  export PATH="${KLM_FLUTTER_ROOT}/bin:${PATH}"
  git config --global --add safe.directory "${KLM_FLUTTER_ROOT}" || true

  local profile="${HOME}/.bashrc"
  local line="export PATH=\"${KLM_FLUTTER_ROOT}/bin:\$PATH\""
  if [ -f "${profile}" ] && ! grep -qF "${KLM_FLUTTER_ROOT}/bin" "${profile}"; then
    printf '\n# Flutter SDK (Kontakt Library Manager)\n%s\n' "${line}" >> "${profile}"
  fi
}

install_flutter
ensure_path

log "Flutter toolchain:"
flutter --version

log "Fetching Dart/Flutter dependencies."
cd "$(dirname "$0")/.."
flutter pub get

log "Bootstrap complete."
