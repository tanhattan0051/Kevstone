# Release scripts — runbook

Scaffolding for Phase 5 (Build & Distribution), per
`docs/superpowers/specs/2026-09-16-keystone-design.md` Part D §3.

**Status: untested.** These scripts were written without a paid Apple
Developer account, a Developer ID Application certificate, or notary
credentials available in this environment. `bash -n` syntax-checks pass and
the logic follows the spec + Apple's documented tool behavior, but nobody has
run a real signed build through them yet. Treat the first real run as a
dry run: read the output carefully, and expect to iron out small issues
(exact certificate name formatting, notarytool output wording, etc.).

## Prerequisites (one-time, on the machine that will build releases)

1. **A paid Apple Developer Program membership** (individual or
   organization). Free accounts cannot get a Developer ID certificate.
2. **A "Developer ID Application" certificate** for your Team, installed in
   your login keychain (Xcode → Settings → Accounts → Manage Certificates →
   "+" → "Developer ID Application", or generate one at
   developer.apple.com/account/resources/certificates and double-click the
   downloaded `.cer` to install it — the private key must already be in
   your keychain, e.g. from the machine that made the CSR).
   Confirm it's there and note the exact name:
   ```
   security find-identity -v -p codesigning
   ```
   You should see a line like:
   `"Developer ID Application: Jane Appleseed (ABCDE12345)"`
   — `Jane Appleseed` is `APPLE_DEV_ID_NAME`, `ABCDE12345` is `APPLE_TEAM_ID`.
3. **A notarytool credential profile named `KEYSTONE_NOTARY`** stored in
   your keychain (this is a one-time, interactive command — do NOT script
   or commit it):
   ```
   xcrun notarytool store-credentials "KEYSTONE_NOTARY" \
       --apple-id "you@example.com" \
       --team-id "ABCDE12345" \
       --password "an-app-specific-password"
   ```
   (Generate the app-specific password at appleid.apple.com → Sign-In and
   Security → App-Specific Passwords.) An App Store Connect API key
   (`--key`/`--key-id`/`--issuer`) works too and is what
   `.github/workflows/release.yml` uses in CI, since it doesn't require an
   interactive Apple ID password.
4. Xcode command line tools installed (`xcode-select --install`) — provides
   `swift`, `codesign`, `iconutil`, `xcrun notarytool`, `xcrun stapler`,
   `spctl`, `hdiutil`.
5. Optional: `brew install create-dmg` for a nicer-looking DMG window
   (custom icon layout/background). `Scripts/make_dmg.sh` falls back to a
   plain `hdiutil`-built DMG if `create-dmg` isn't installed — functionally
   equivalent, just plainer.

## Release order

Run these from the repo root, in order. Each script fails loudly (missing
env var, missing input file, verification failure) rather than silently
producing a broken artifact — stop and fix the reported problem before
continuing.

```bash
# 1. Build the unsigned .app from the SPM release binary + Info.plist + icon.
Scripts/build_app.sh dist
#    -> dist/Keystone.app

# 2. Codesign with your Developer ID Application cert, Hardened Runtime,
#    and App/Keystone.entitlements. Verifies the signature afterwards.
APPLE_DEV_ID_NAME="Jane Appleseed" \
APPLE_TEAM_ID="ABCDE12345" \
Scripts/sign.sh dist/Keystone.app

# 3. Package the signed .app + an /Applications symlink into a DMG.
Scripts/make_dmg.sh dist/Keystone.app dist/Keystone.dmg
#    -> dist/Keystone.dmg

# 4. Submit for notarization, wait, staple the ticket, verify with spctl.
KEYSTONE_NOTARY=KEYSTONE_NOTARY \
Scripts/notarize.sh dist/Keystone.dmg
#    -> dist/Keystone.dmg is now notarized + stapled, ready to distribute.
```

After step 4, `dist/Keystone.dmg` can be uploaded anywhere (GitHub Releases,
a static host, etc.) and will pass Gatekeeper offline on a fresh Mac.

## CI (`.github/workflows/release.yml`)

Pushing a tag matching `v*` (e.g. `v1.0.0`) triggers `.github/workflows/release.yml`,
which runs the same four scripts on a `macos-15` GitHub-hosted runner and
attaches the resulting DMG to a (draft) GitHub Release. It is separate from
`.github/workflows/ci.yml` (the fast, secret-free engine/input test suite
that runs on every push/PR) so ordinary contributions never need signing
credentials.

The release workflow only does real work if all of these repo secrets are
set (Settings → Secrets and variables → Actions); otherwise it no-ops with a
warning instead of failing:

- `APPLE_DEV_ID_NAME`, `APPLE_TEAM_ID` — same as above.
- `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD` — your
  Developer ID Application cert + private key, exported from Keychain
  Access as a password-protected `.p12`, then base64-encoded
  (`base64 -i DeveloperID.p12 | pbcopy`) into the secret.
- `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, `APPLE_NOTARY_KEY_P8_BASE64` —
  an App Store Connect API key (App Store Connect → Users and Access →
  Integrations → Keys) with at least the "Developer" role, base64-encoded
  the same way.

See the comment header at the top of `.github/workflows/release.yml` for
the full list and how each one is used.

## Sparkle (self-update) — not yet wired up

The spec (Part D §3, "Self-update: Sparkle") calls for Sparkle 2 as a later
addition, not part of Phase 5 scaffolding. When it's added:

- It ships an XPC helper that must itself be signed (same Developer ID,
  Hardened Runtime) — `Scripts/sign.sh` already signs anything found under
  `Contents/Frameworks` and `Contents/XPCServices` before the main bundle,
  so it should pick up Sparkle's helper automatically once it's embedded by
  the build step, but double-check against Sparkle's current docs for any
  additional hardened-runtime entitlements its XPC services need (those
  would go in `App/Keystone.entitlements`, or a separate entitlements file
  for the helper — Sparkle's own build scripts usually handle this).
- Needs a Sparkle EdDSA keypair (kept out of the repo, like everything else
  here) to sign the `appcast.xml` feed and each release's update payload.
- `Scripts/build_app.sh` will need to copy Sparkle.framework into
  `Contents/Frameworks` once it's added as an SPM dependency.

None of that is implemented yet — this is a pointer for whoever picks it up.
