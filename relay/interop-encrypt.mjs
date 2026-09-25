// Encrypts a sample OTP message exactly as the phone will, per PROTOCOL.md:
// AES-256-GCM, AAD = utf8(room), ct = ciphertext||tag, base64.
// Prints:  <keyB64> <room> <nonceB64> <ctB64> <plaintext>
import crypto from "node:crypto";

const key = crypto.randomBytes(32);
const room = crypto.randomBytes(16).toString("hex");
const plaintext = JSON.stringify({
  id: "test-1", ts: Date.now(), source: "SMS", sender: "VM-HDFCBK",
  title: "HDFC Bank", text: "Your OTP is 483920. Valid 10 min.", code: "483920",
});

const iv = crypto.randomBytes(12);
const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
cipher.setAAD(Buffer.from(room, "utf8"));
const ct = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
const tag = cipher.getAuthTag();
const ctFull = Buffer.concat([ct, tag]);

process.stdout.write(
  [key.toString("base64"), room, iv.toString("base64"),
   ctFull.toString("base64"), plaintext].join("\n")
);
