#!/usr/bin/env bash
#
# build_app.sh — assemble Keystone.app from the SPM `Keystone` executable.
#
# Design spec: docs/superpowers/specs/2026-09-16-keystone-design.md, Part D §3.
#
# What this does NOT do: sign, notarize, or package a DMG. Those are separate
# steps (Scripts/sign.sh, Scripts/notarize.sh, Scripts/make_dmg.sh) so each
# stage can be re-run independently. See Scripts/README.md for the full
# release order.
#
# Usage:
#   Scripts/build_app.sh [output-dir]
#   OUTPUT_DIR=/path/to/dist Scripts/build_app.sh
#
# The positional argument, if given, wins over $OUTPUT_DIR. Default is
# "./dist" (relative to the repo root). The result is:
#   <output-dir>/Keystone.app/Contents/MacOS/Keystone
#   <output-dir>/Keystone.app/Contents/Info.plist
#   <output-dir>/Keystone.app/Contents/Resources/AppIcon.icns   (if iconutil available)
#
# This script is safe to re-run: it removes any previous Keystone.app in the
# output dir before assembling a fresh one.

set -euo pipefail

# --- Resolve paths -----------------------------------------------------
# Repo root = parent of this script's directory (Scripts/..), so the script
# works no matter what directory it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="Keystone"
BUNDLE_ID="com.tanta.keystone"
SCHEME_TARGET="Keystone"   # SPM executable product name (Package.swift)

OUTPUT_DIR="${1:-${OUTPUT_DIR:-${REPO_ROOT}/dist}}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "==> Repo root:    ${REPO_ROOT}"
echo "==> Output dir:   ${OUTPUT_DIR}"
echo "==> App bundle:   ${APP_BUNDLE}"

# --- Sanity checks -------------------------------------------------------
if ! command -v swift >/dev/null 2>&1; then
    echo "error: 'swift' not found in PATH. Install Xcode / the Swift toolchain." >&2
    exit 1
fi

if [[ ! -f "${REPO_ROOT}/App/Info.plist" ]]; then
    echo "error: ${REPO_ROOT}/App/Info.plist not found." >&2
    exit 1
fi

# --- 1. Build the release binary -----------------------------------------
echo "==> swift build -c release (product: ${SCHEME_TARGET})"
(
    cd "${REPO_ROOT}"
    swift build -c release --product "${SCHEME_TARGET}"
)

# Ask SwiftPM where it put the release binaries rather than hardcoding
# .build/release, which can differ (e.g. cross-compiled / custom --scratch-path).
BIN_PATH="$(cd "${REPO_ROOT}" && swift build -c release --show-bin-path)"
BUILT_BINARY="${BIN_PATH}/${SCHEME_TARGET}"

if [[ ! -x "${BUILT_BINARY}" ]]; then
    echo "error: expected built binary at ${BUILT_BINARY} but it's missing/not executable." >&2
    exit 1
fi

# --- 2. Lay out the .app bundle skeleton ----------------------------------
echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# --- 3. Copy the executable ------------------------------------------------
cp "${BUILT_BINARY}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# --- 4. Copy + patch Info.plist --------------------------------------------
# We copy the checked-in App/Info.plist verbatim (it is the source of truth
# for bundle id / LSUIElement / min OS) and only ADD the packaging-specific
# keys that don't make sense for `swift run` (executable name, icon file,
# bundle type, version numbers) if they're not already present. This never
# modifies the source file under App/ — only the copy inside the built
# .app bundle.
DEST_PLIST="${APP_BUNDLE}/Contents/Info.plist"
cp "${REPO_ROOT}/App/Info.plist" "${DEST_PLIST}"

PLIST_BUDDY="/usr/libexec/PlistBuddy"
if [[ -x "${PLIST_BUDDY}" ]]; then
    # Helper: add a key only if it doesn't already exist (so an Info.plist
    # that later grows explicit values for these keys is respected as-is).
    add_if_missing() {
        local key="$1" type="$2" value="$3"
        if ! "${PLIST_BUDDY}" -c "Print :${key}" "${DEST_PLIST}" >/dev/null 2>&1; then
            "${PLIST_BUDDY}" -c "Add :${key} ${type} ${value}" "${DEST_PLIST}"
        fi
    }

    add_if_missing "CFBundleExecutable"        string "${APP_NAME}"
    add_if_missing "CFBundlePackageType"       string "APPL"
    add_if_missing "CFBundleIdentifier"        string "${BUNDLE_ID}"
    add_if_missing "CFBundleShortVersionString" string "1.0"
    add_if_missing "CFBundleVersion"           string "1"
    add_if_missing "CFBundleIconFile"          string "AppIcon"
else
    echo "warning: /usr/libexec/PlistBuddy not found; Info.plist copied as-is." >&2
    echo "         Make sure it already sets CFBundleExecutable/CFBundlePackageType/CFBundleIconFile." >&2
fi

# --- 5. Build & copy the app icon (.icns) ----------------------------------
# iconutil needs an *.iconset* directory with Apple's exact filename
# convention (icon_16x16.png, icon_16x16@2x.png, ...), which differs from
# our Design/AppIcon.appiconset (Xcode's asset-catalog convention, driven by
# Contents.json). We stage a throwaway .iconset dir with the right names,
# built from the same source PNGs, then hand it to iconutil.
ICONSET_SRC="${REPO_ROOT}/Design/AppIcon.appiconset"
ICON_OUT="${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

if command -v iconutil >/dev/null 2>&1 && [[ -d "${ICONSET_SRC}" ]]; then
    echo "==> Building AppIcon.icns via iconutil"
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "${TMP_ICONSET}"

    # Mapping mirrors Design/AppIcon.appiconset/Contents.json.
    # left = iconutil-required filename, right = our source PNG.
    declare -a ICON_MAP=(
        "icon_16x16.png:icon_16.png"
        "icon_16x16@2x.png:icon_32.png"
        "icon_32x32.png:icon_32.png"
        "icon_32x32@2x.png:icon_64.png"
        "icon_128x128.png:icon_128.png"
        "icon_128x128@2x.png:icon_256.png"
        "icon_256x256.png:icon_256.png"
        "icon_256x256@2x.png:icon_512.png"
        "icon_512x512.png:icon_512.png"
        "icon_512x512@2x.png:icon_1024.png"
    )

    missing_source=0
    for pair in "${ICON_MAP[@]}"; do
        dest_name="${pair%%:*}"
        src_name="${pair##*:}"
        src_path="${ICONSET_SRC}/${src_name}"
        if [[ -f "${src_path}" ]]; then
            cp "${src_path}" "${TMP_ICONSET}/${dest_name}"
        else
            echo "warning: missing icon source ${src_path}" >&2
            missing_source=1
        fi
    done

    if [[ "${missing_source}" -eq 0 ]]; then
        iconutil -c icns "${TMP_ICONSET}" -o "${ICON_OUT}"
        echo "==> Wrote ${ICON_OUT}"
    else
        echo "warning: skipping .icns generation, one or more source PNGs missing." >&2
    fi
    rm -rf "$(dirname "${TMP_ICONSET}")"
else
    echo "note: iconutil not found or ${ICONSET_SRC} missing — skipping app icon." >&2
    echo "      The app will build and run without a custom Finder/Dock icon." >&2
fi

echo "==> Done. Unsigned app bundle at: ${APP_BUNDLE}"
echo "    Next: Scripts/sign.sh \"${APP_BUNDLE}\""
