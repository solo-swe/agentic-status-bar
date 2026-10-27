// Checks that a Sparkle EdDSA private key file (as `generate_keys -x` exports it) belongs to a public key, so a
// release is never signed with a key the installed apps don't trust.
//
//   swift scripts/check-sparkle-key.swift <private key file> <public key, base64>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: swift scripts/check-sparkle-key.swift <private key file> <public key>\n".data(using: .utf8)!)
    exit(2)
}
let text = (try? String(contentsOfFile: args[1], encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
// The export is the base64 32-byte seed; older exports append the 32-byte public key.
guard let data = Data(base64Encoded: text), data.count == 32 || data.count == 64,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data.prefix(32)) else {
    FileHandle.standardError.write("The Sparkle private key file isn't a base64 Ed25519 key\n".data(using: .utf8)!)
    exit(1)
}
guard key.publicKey.rawRepresentation.base64EncodedString() == args[2] else {
    FileHandle.standardError.write("The Sparkle private key doesn't match SPARKLE_PUBLIC_KEY\n".data(using: .utf8)!)
    exit(1)
}
print("Sparkle key pair matches")
