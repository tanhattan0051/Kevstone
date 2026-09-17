#!/usr/bin/env bash
#
# make_dmg.sh — package a signed Keystone.app into a drag-to-install DMG
# (app + /Applications symlink).
#
# Design spec: docs/superpowers/specs/2026-09-16-keystone-design.md, Part D §3
# ("Packaging: DMG").
#
# IMPORTANT ordering: sign Keystone.app BEFORE running this script
# (Scripts/sign.sh). This script only packages what's given to it; it does
# not sign anything itself. The resulting DMG gets notarized+stapled
# afterwards by Scripts/notarize.sh.
#
# Usage:
#   Scripts/make_dmg.sh <path-to-signed-Keystone.app> [output-dmg-path]
#
# If output-dmg-path is omitted, defaults to
# "<dir of the .app>/Keystone.dmg".
#
# Uses `create-dmg` (https://github.com/create-dmg/create-dmg, installable
# via `brew install create-dmg`) if it's on PATH, for a nicer Finder window
# (icon layout/background). Otherwise falls back to a plain `hdiutil`
# staging-folder DMG, which is functionally equivalent (app + /Applications
# symlink) but without custom window chrome.

set -euo pipefail

APP_BUNDLE="${1:-}"
VOLUME_NAME="Keystone"
APP_NAME="Keystone.app"

if [[ -z "${APP_BUNDLE}" ]]; then
    echo "usage: $(basename "$0") <path-to-signed-Keystone.app> [output-dmg-path]" >&2
    exit 1
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "error: app bundle not found at '${APP_BUNDLE}'." >&2
    exit 1
fi

# Sanity check: warn (but don't block) if the app doesn't look signed yet —
# make_dmg.sh doesn't sign, so an unsigned app here means the DMG's contents
# will fail Gatekeeper/notarization later.
if ! codesign --verify --quiet "${APP_BUNDLE}" 2>/dev/null; then
    echo "warning: '${APP_BUNDLE}' does not appear to be signed yet." >&2
    echo "         Run Scripts/sign.sh before packaging for a real release." >&2
fi

DEFAULT_OUT_DIR="$(cd "$(dirname "${APP_BUNDLE}")" && pwd)"
OUTPUT_DMG="${2:-${DEFAULT_OUT_DIR}/Keystone.dmg}"

echo "==> App bundle: ${APP_BUNDLE}"
echo "==> Output DMG: ${OUTPUT_DMG}"

rm -f "${OUTPUT_DMG}"

if command -v create-dmg >/dev/null 2>&1; then
    # --- Preferred path: create-dmg ---------------------------------------
    echo "==> Using create-dmg"
    create-dmg \
        --volname "${VOLUME_NAME}" \
        --app-drop-link 450 150 \
        --icon "${APP_NAME}" 150 150 \
        --window-size 600 300 \
        --hide-extension "${APP_NAME}" \
        "${OUTPUT_DMG}" \
        "${APP_BUNDLE}" \
        || {
            # create-dmg exits non-zero on some benign warnings (e.g. no Finder
            # window could be styled in a headless CI context); only treat it
            # as fatal if the DMG wasn't actually produced.
            if [[ ! -f "${OUTPUT_DMG}" ]]; then
                echo "error: create-dmg failed and no DMG was produced." >&2
                exit 1
            fi
            echo "warning: create-dmg reported a non-zero exit but produced a DMG; continuing." >&2
        }
else
    # --- Fallback path: plain hdiutil staging folder ----------------------
    echo "==> create-dmg not found; falling back to hdiutil (brew install create-dmg for nicer window chrome)"

    STAGING_DIR="$(mktemp -d)/dmg-staging"
    mkdir -p "${STAGING_DIR}"

    # Copy (not move) the app into the staging area so the caller's signed
    # bundle is left untouched.
    cp -R "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}"

    # The drag-to-install affordance: a symlink to /Applications sitting
    # next to the app in the same Finder window.
    ln -s /Applications "${STAGING_DIR}/Applications"

    hdiutil create \
        -volname "${VOLUME_NAME}" \
        -srcfolder "${STAGING_DIR}" \
        -ov -format UDZO \
        "${OUTPUT_DMG}"

    rm -rf "$(dirname "${STAGING_DIR}")"
fi

if [[ ! -f "${OUTPUT_DMG}" ]]; then
    echo "error: expected DMG at '${OUTPUT_DMG}' but it wasn't created." >&2
    exit 1
fi

echo "==> Done: ${OUTPUT_DMG}"
echo "    Next: Scripts/notarize.sh \"${OUTPUT_DMG}\""
