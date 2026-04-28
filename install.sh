#!/usr/bin/env bash
# tca-graph one-shot installer.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/tornikegomareli/tca-graph/main/install.sh | bash
#
# Or:
#   curl -sSL https://raw.githubusercontent.com/tornikegomareli/tca-graph/main/install.sh | bash -s -- --prefix /usr/local
#
# Detects the latest release on GitHub, downloads the macOS arm64 tarball,
# verifies its SHA-256 checksum, and installs the binary plus its viewer
# bundle into the chosen prefix. Defaults to ~/.local so no sudo is needed
# and no system locations are touched.
set -euo pipefail

REPO="tornikegomareli/tca-graph"
PREFIX="${HOME}/.local"
VERSION=""
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"; shift 2 ;;
    --version)
      VERSION="$2"; shift 2 ;;
    --quiet)
      QUIET=1; shift ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1 ;;
  esac
done

log() { [[ $QUIET -eq 1 ]] || echo "$@"; }
err() { echo "error: $*" >&2; exit 1; }

# Sanity checks.
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "tca-graph currently ships macOS binaries only (you are on $(uname -s))."
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  err "tca-graph currently ships arm64 binaries only (you are on $(uname -m)). Build from source: https://github.com/${REPO}"
fi
command -v curl >/dev/null || err "curl is required"
command -v tar  >/dev/null || err "tar is required"
command -v shasum >/dev/null || err "shasum is required"

# Resolve version.
if [[ -z "${VERSION}" ]]; then
  log "Resolving latest release for ${REPO}..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -1)"
  [[ -n "${VERSION}" ]] || err "could not detect latest release"
fi

ASSET="tca-graph-${VERSION}-macos-arm64.tar.gz"
URL_BASE="https://github.com/${REPO}/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

log "Downloading ${ASSET}..."
curl -fSL "${URL_BASE}/${ASSET}" -o "${TMP}/${ASSET}"
curl -fSL "${URL_BASE}/${ASSET}.sha256" -o "${TMP}/${ASSET}.sha256"

log "Verifying checksum..."
( cd "${TMP}" && shasum -a 256 -c "${ASSET}.sha256" ) || err "checksum mismatch — refusing to install"

log "Extracting..."
tar xzf "${TMP}/${ASSET}" -C "${TMP}"
EXTRACTED="${TMP}/tca-graph-${VERSION}-macos-arm64"
[[ -d "${EXTRACTED}" ]] || err "tarball did not contain expected directory tca-graph-${VERSION}-macos-arm64"

log "Installing into ${PREFIX}/bin and ${PREFIX}/share/tca-graph..."
mkdir -p "${PREFIX}/bin" "${PREFIX}/share/tca-graph"
cp "${EXTRACTED}/bin/tca-graph" "${PREFIX}/bin/"
if [[ -d "${EXTRACTED}/bin/tca-graph_TCAGraphCLI.bundle" ]]; then
  rm -rf "${PREFIX}/bin/tca-graph_TCAGraphCLI.bundle"
  cp -R "${EXTRACTED}/bin/tca-graph_TCAGraphCLI.bundle" "${PREFIX}/bin/"
fi
if [[ -d "${EXTRACTED}/share/tca-graph/viewer" ]]; then
  rm -rf "${PREFIX}/share/tca-graph/viewer"
  cp -R "${EXTRACTED}/share/tca-graph/viewer" "${PREFIX}/share/tca-graph/"
fi
chmod +x "${PREFIX}/bin/tca-graph"

# macOS quarantine attribute may have been added during the curl download;
# strip it so the binary runs without a Gatekeeper prompt.
xattr -d com.apple.quarantine "${PREFIX}/bin/tca-graph" 2>/dev/null || true

log ""
log "Installed tca-graph ${VERSION} to ${PREFIX}/bin/tca-graph."
if ! command -v tca-graph >/dev/null 2>&1; then
  log "${PREFIX}/bin is not on your PATH. Add it with:"
  log "  export PATH=\"${PREFIX}/bin:\${PATH}\""
fi
log ""
log "Try it: tca-graph serve <path-to-your-TCA-project>"
