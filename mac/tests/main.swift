import Foundation
// Standalone decrypt harness for cross-platform interop testing.
// argv: <keyBase64> <room> <nonceB64> <ctB64>  ->  prints plaintext to stdout.
let a = CommandLine.arguments
let crypto = try Crypto(keyBase64: a[1], room: a[2])
let plaintext = try crypto.open(nonceB64: a[3], ctB64: a[4])
FileHandle.standardOutput.write(plaintext)
