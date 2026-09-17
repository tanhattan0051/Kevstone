#!/usr/bin/env bash
#
# sign.sh — codesign Keystone.app with a Developer ID Application certificate,
# Hardened Runtime, and the minimal entitlements from App/Keystone.entitlements.
#
# Design spec: docs/superpowers/specs/2026-09-16-keystone-design.md, Part D §3
# ("Signing").
#
# This requires a paid Apple Developer Program membership and a
# "Developer ID Application: <Name> (<TEAMID>)" identity already present in
# your login keychain (Xcode > Settings > Accounts, or manually imported).
# It CANNOT be exercised in this environment — there is no certificate here.
#
# Usage:
#   APPLE_DEV_ID_NAME="Your Name" \
#   APPLE_TEAM_ID="ABCDE12345" \
#   Scripts/sign.sh path/to/Keystone.app
#
# Required env vars:
#   APPLE_DEV_ID_NAME  - the human-readable name on the Developer ID
#                        Application certificate, e.g. "Jane Appleseed" or
#                        "Jane Appleseed LLC" (exactly as it appears in
#                        `security find-identity -v -p codesigning`).
#   APPLE_TEAM_ID      - your 10-character Apple Developer Team ID.
#
# Together these form the identity string:
#   "Developer ID Application: <APPLE_DEV_ID_NAME> (<APPLE_TEAM_ID>)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_BUNDLE="${1:-}"
ENTITLEMENTS="${REPO_ROOT}/App/Keystone.entitlements"

# --- Validate inputs -------------------------------------------------------
if [[ -z "${APP_BUNDLE}" ]]; then
    echo "usage: $(basename "$0") <path-to-Keystone.app>" >&2
    exit 1
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "error: app bundle not found at '${APP_BUNDLE}'. Run Scripts/build_app.sh first." >&2
    exit 1
fi

if [[ ! -f "${ENTITLEMENTS}" ]]; then
    echo "error: entitlements file not found at '${ENTITLEMENTS}'." >&2
    exit 1
fi

: "${APPLE_DEV_ID_NAME:?error: APPLE_DEV_ID_NAME is not set. Export it, e.g. APPLE_DEV_ID_NAME=\"Jane Appleseed\". Find the exact name with: security find-identity -v -p codesigning}"
: "${APPLE_TEAM_ID:?error: APPLE_TEAM_ID is not set. Export it, e.g. APPLE_TEAM_ID=ABCDE12345 (Apple Developer > Membership > Team ID).}"

IDENTITY="Developer ID Application: ${APPLE_DEV_ID_NAME} (${APPLE_TEAM_ID})"

if ! command -v codesign >/dev/null 2>&1; then
    echo "error: 'codesign' not found. This script must run on macOS with Xcode command line tools installed." >&2
    exit 1
fi

echo "==> Signing identity: ${IDENTITY}"
echo "==> App bundle:       ${APP_BUNDLE}"
echo "==> Entitlements:     ${ENTITLEMENTS}"

# Fail loudly (rather than silently producing an unsigned/ad-hoc-signed app)
# if the identity string doesn't match anything in the keychain.
if ! security find-identity -v -p codesigning | grep -qF "${IDENTITY}"; then
    echo "error: no matching codesigning identity found in the keychain for:" >&2
    echo "         ${IDENTITY}" >&2
    echo "       Run 'security find-identity -v -p codesigning' to see what's available," >&2
    echo "       and double check APPLE_DEV_ID_NAME / APPLE_TEAM_ID." >&2
    exit 1
fi

# --- Sign inside-out ---------------------------------------------------
# Hardened Runtime + Developer ID requires every executable component to be
# signed before the outer bundle: frameworks/dylibs/XPC helpers/plugins
# first, then the main app. Keystone currently ships no embedded
# frameworks or XPC helpers (Sparkle, if/when added in a later phase, will
# introduce some — sign those here too, before the final `codesign` call
# below, following Sparkle's own signing docs).
#
# Sign any embedded frameworks/XPC services under Contents/Frameworks and
# Contents/XPCServices first, if present, so this script keeps working once
# Sparkle (or anything else with embedded code) is added.
if [[ -d "${APP_BUNDLE}/Contents/Frameworks" ]]; then
    echo "==> Signing embedded frameworks"
    find "${APP_BUNDLE}/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 \
        | while IFS= read -r -d '' item; do
            echo "    - ${item#${APP_BUNDLE}/}"
            codesign --force --options runtime --timestamp \
                --sign "${IDENTITY}" \
                "${item}"
        done
fi

if [[ -d "${APP_BUNDLE}/Contents/XPCServices" ]]; then
    echo "==> Signing embedded XPC services"
    find "${APP_BUNDLE}/Contents/XPCServices" -maxdepth 1 -name "*.xpc" -print0 \
        | while IFS= read -r -d '' item; do
            echo "    - ${item#${APP_BUNDLE}/}"
            codesign --force --options runtime --timestamp \
                --sign "${IDENTITY}" \
                "${item}"
        done
fi

# Finally, sign the main app bundle itself with our entitlements.
echo "==> Signing main app bundle"
codesign --force --options runtime --timestamp \
    --sign "${IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" \
    "${APP_BUNDLE}"

# --- Verify ---------------------------------------------------------------
echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Signature details:"
codesign --display --verbose=4 "${APP_BUNDLE}"

echo "==> OK: ${APP_BUNDLE} is signed."
echo "    Next: Scripts/make_dmg.sh \"${APP_BUNDLE}\""
