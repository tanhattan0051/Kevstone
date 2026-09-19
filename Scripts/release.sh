#!/usr/bin/env bash
#
# release.sh — cut a Keystone release the built-in auto-updater can consume.
#
# Steps: build the versioned .app → codesign → zip → sign the zip with the
# Ed25519 update key → create the GitHub Release with Keystone.zip +
# Keystone.zip.sig. The app verifies that Ed25519 signature (embedded public
# key) before installing any update — see App/Updater.swift.
#
# Usage:
#   Scripts/release.sh <version>            # e.g. Scripts/release.sh 1.0.1
#
# Env (optional):
#   KEYSTONE_SIGN_IDENTITY   codesign identity. Default "-" (ad-hoc). Set to a
#                            stable self-signed identity name (e.g.
#                            "Keystone Self-Signed") so Accessibility grants
#                            persist across auto-updates.
#   KEYSTONE_ED25519_KEY     path to the base64 Ed25519 private key.
#                            Default: ~/.config/keystone/ed25519_private.b64
#   KEYSTONE_REPO            GitHub repo. Default: tanhattan0051/Keystone

set -euo pipefail

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
    echo "usage: Scripts/release.sh <version>   (e.g. 1.0.1)" >&2
    exit 2
fi
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must be MAJOR.MINOR.PATCH (got '${VERSION}')" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST="${REPO_ROOT}/dist"
APP="${DIST}/Keystone.app"
ZIP="${DIST}/Keystone.zip"
SIG="${DIST}/Keystone.zip.sig"

SIGN_IDENTITY="${KEYSTONE_SIGN_IDENTITY:--}"
PRIV_KEY="${KEYSTONE_ED25519_KEY:-${HOME}/.config/keystone/ed25519_private.b64}"
REPO="${KEYSTONE_REPO:-tanhattan0051/Keystone}"

for tool in swift ditto codesign gh; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "error: '${tool}' not found in PATH" >&2; exit 1; }
done
[[ -f "${PRIV_KEY}" ]] || { echo "error: Ed25519 private key not found at ${PRIV_KEY}" >&2; exit 1; }

echo "==> Building Keystone.app v${VERSION}"
KEYSTONE_VERSION="${VERSION}" bash "${SCRIPT_DIR}/build_app.sh" "${DIST}"

echo "==> Codesigning (${SIGN_IDENTITY})"
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP}"
codesign --verify --verbose=1 "${APP}"

echo "==> Zipping -> ${ZIP}"
rm -f "${ZIP}" "${SIG}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "==> Signing the zip with the Ed25519 update key"
swift "${SCRIPT_DIR}/sign_update.swift" "${PRIV_KEY}" "${ZIP}" > "${SIG}"
echo "    signature: $(cat "${SIG}")"

echo "==> Creating GitHub Release v${VERSION} on ${REPO}"
NOTES="$(cat <<NOTE
Keystone v${VERSION}

Cài đặt lần đầu: tải Keystone.zip, giải nén, kéo Keystone.app vào /Applications.
Vì app chưa notarize (không có tài khoản Apple Developer), lần đầu macOS sẽ cảnh
báo — **chuột phải vào Keystone.app → Mở** (chỉ cần một lần). Từ các bản sau, app
tự cập nhật (đã xác thực bằng chữ ký Ed25519).
NOTE
)"

gh release create "v${VERSION}" "${ZIP}" "${SIG}" \
    --repo "${REPO}" \
    --title "Keystone v${VERSION}" \
    --notes "${NOTES}"

echo "==> Done. Release v${VERSION} published with Keystone.zip + Keystone.zip.sig."
