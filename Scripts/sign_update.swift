#!/usr/bin/env swift
//
// sign_update.swift — sign an update archive with the Ed25519 update-signing
// key, printing the base64 signature to stdout. Used by Scripts/release.sh.
//
// The app embeds the matching PUBLIC key and verifies this signature before
// installing any update (see App/Updater.swift / KeystoneInput/UpdateCheck).
// The PRIVATE key lives OUTSIDE the repo (default ~/.config/keystone/
// ed25519_private.b64) and must never be committed — losing it means you can
// no longer sign updates the installed apps will accept.
//
// Usage:
//   swift Scripts/sign_update.swift <private-key-base64-file> <file-to-sign>
// Example:
//   swift Scripts/sign_update.swift ~/.config/keystone/ed25519_private.b64 dist/Keystone.zip

import Foundation
import CryptoKit

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    die("usage: sign_update.swift <private-key-base64-file> <file-to-sign>")
}

let keyPath = (args[1] as NSString).expandingTildeInPath
guard let keyText = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
    die("cannot read private key at \(keyPath)")
}
guard let keyData = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    die("private key is not valid base64")
}
guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    die("private key bytes are not a valid Ed25519 key (expected 32 raw bytes, base64-encoded)")
}
guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else {
    die("cannot read file to sign: \(args[2])")
}
guard let sig = try? key.signature(for: fileData) else {
    die("signing failed")
}
print(sig.base64EncodedString())
