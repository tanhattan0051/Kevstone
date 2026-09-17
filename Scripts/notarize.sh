#!/usr/bin/env bash
#
# notarize.sh — submit the DMG to Apple notary service, wait for the result,
# staple the ticket, and verify Gatekeeper acceptance.
#
# Design spec: docs/superpowers/specs/2026-09-16-keystone-design.md, Part D §3
# ("Notarization + stapling").
#
# Prerequisite: a notarytool credential profile stored in the local keychain,
# created once (interactively, NOT by this script) with either an
# App Store Connect API key or an app-specific password:
#
#   xcrun notarytool store-credentials "KEYSTONE_NOTARY" \
#       --apple-id "you@example.com" \
#       --team-id "ABCDE12345" \
#       --password "app-specific-password"
#
#   # or, with an API key:
#   xcrun notarytool store-credentials "KEYSTONE_NOTARY" \
#       --key "/path/to/AuthKey_XXXX.p8" \
#       --key-id "XXXXXXXXXX" \
#       --issuer "issuer-uuid"
#
# That command is interactive/one-time and deliberately NOT part of this
# script or committed anywhere — it writes the credential into the local
# keychain, never into a file this repo could accidentally ship.
#
# Usage:
#   KEYSTONE_NOTARY=KEYSTONE_NOTARY Scripts/notarize.sh path/to/Keystone.dmg
#
# Required env vars:
#   KEYSTONE_NOTARY - name of the notarytool keychain profile to use
#                     (see `xcrun notarytool store-credentials` above).
#                     Defaults to "KEYSTONE_NOTARY" if unset, matching the
#                     spec's recommended profile name — but must exist in
#                     the keychain of the machine running this script.

set -euo pipefail

DMG_PATH="${1:-}"
PROFILE_NAME="${KEYSTONE_NOTARY:-KEYSTONE_NOTARY}"

if [[ -z "${DMG_PATH}" ]]; then
    echo "usage: KEYSTONE_NOTARY=<profile> $(basename "$0") <path-to-Keystone.dmg>" >&2
    exit 1
fi

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "error: DMG not found at '${DMG_PATH}'. Run Scripts/make_dmg.sh first." >&2
    exit 1
fi

if [[ -z "${PROFILE_NAME}" ]]; then
    echo "error: KEYSTONE_NOTARY keychain profile name is empty." >&2
    exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: 'xcrun' not found. This must run on macOS with Xcode command line tools installed." >&2
    exit 1
fi

echo "==> DMG:                ${DMG_PATH}"
echo "==> Notary profile:     ${PROFILE_NAME}"

# --- 1. Submit and wait ---------------------------------------------------
# --wait blocks until Apple's notary service finishes processing (typically
# minutes). Capture output so we can surface the submission id on failure
# (useful for `xcrun notarytool log <id>` follow-up) without parsing JSON.
echo "==> Submitting for notarization (this can take several minutes)..."
SUBMIT_LOG="$(mktemp)"
trap 'rm -f "${SUBMIT_LOG}"' EXIT

if ! xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${PROFILE_NAME}" \
        --wait \
        | tee "${SUBMIT_LOG}"; then
    echo "error: notarytool submit failed. See output above." >&2
    exit 1
fi

if ! grep -q "status: Accepted" "${SUBMIT_LOG}"; then
    echo "error: notarization did not report 'Accepted'. Full log:" >&2
    cat "${SUBMIT_LOG}" >&2
    SUBMISSION_ID="$(grep -o 'id: [a-f0-9-]\{36\}' "${SUBMIT_LOG}" | head -1 | awk '{print $2}' || true)"
    if [[ -n "${SUBMISSION_ID}" ]]; then
        echo "       For details: xcrun notarytool log ${SUBMISSION_ID} --keychain-profile \"${PROFILE_NAME}\"" >&2
    fi
    exit 1
fi

echo "==> Notarization accepted."

# --- 2. Staple the ticket --------------------------------------------------
# Staples the notarization ticket onto the DMG itself so Gatekeeper can
# verify it offline (no network round-trip on the end user's first launch).
echo "==> Stapling ticket"
xcrun stapler staple "${DMG_PATH}"

echo "==> Validating staple"
xcrun stapler validate "${DMG_PATH}"

# --- 3. Gatekeeper assessment ----------------------------------------------
echo "==> Gatekeeper assessment (spctl)"
spctl -a -vvv -t install "${DMG_PATH}"

echo "==> OK: ${DMG_PATH} is notarized, stapled, and passes Gatekeeper."
echo "    Ready to upload as a release asset."
