# OTP Bridge — Protocol

Personal-use, single-pair. One Android phone forwards OTPs to one Mac.
Transport is **LAN first, relay fallback**. All payloads are end-to-end
encrypted with a pre-shared key; neither the relay nor the LAN path ever
sees plaintext.

## 1. Pairing

The Mac is the source of truth for the key. On first launch it generates:

- `key`   — 32 random bytes (AES-256 key), **standard base64** encoded.
- `room`  — 16-byte random id, hex encoded. Identifies this pair on the relay.
- `relay` — WebSocket URL of the relay, e.g. `wss://otp-relay.example.com`.
- `name`  — human label for the Mac, e.g. `"Hari's MacBook"`.

These are encoded as JSON and rendered as a QR code:

```json
{ "v": 1, "key": "<base64 32 bytes>", "room": "<hex 16 bytes>",
  "relay": "wss://...", "name": "Hari's MacBook" }
```

The phone scans it once and stores all four values. That's the whole
handshake — the key never travels over any network.

## 2. Plaintext message (before encryption)

```json
{
  "id":     "<uuid>",           // dedupe key
  "ts":     1727280000000,      // epoch millis, sender clock
  "source": "SMS",              // "SMS" or an Android package name
  "sender": "VM-HDFCBK",        // SMS originator or app label
  "title":  "HDFC Bank",        // optional
  "text":   "Your OTP is 483920. Valid 10 min.",
  "code":   "483920"            // extracted OTP, may be null
}
```

## 3. Wire envelope (what actually crosses the network)

Same shape on both LAN and relay so the Mac has one decrypt path.

```json
{
  "room":  "<hex 16 bytes>",
  "nonce": "<base64 12 bytes>",   // random per message
  "ct":    "<base64 ciphertext||tag>"
}
```

- Cipher: **AES-256-GCM**.
- Key: the shared `key` from pairing.
- Nonce: 12 random bytes, fresh per message.
- AAD: the UTF-8 bytes of the `room` hex string (binds ciphertext to the pair).
- `ct` = ciphertext followed by the 16-byte GCM tag, base64 (standard).

## 4. LAN path

- Mac advertises a Bonjour service `_otpbridge._tcp` on a random port and
  runs a TCP listener.
- Phone resolves the service via Android NSD, opens a TCP socket, and writes
  the envelope as a single line of JSON terminated by `\n` (newline-delimited
  JSON). One message per connection is fine; the phone may keep the socket
  open and send more lines.

## 5. Relay path (fallback)

WebSocket. Text frames, each frame is one JSON object.

- On connect a client sends: `{ "type":"join", "room":"<hex>" }`
- To send:                    `{ "type":"msg", "room":"<hex>", "nonce":"...", "ct":"..." }`
- The relay forwards every `msg` to all *other* sockets joined to the same
  room. It stores nothing and cannot decrypt anything.

## 6. Delivery strategy

- Phone tries LAN (NSD resolves within a short timeout). If it resolves,
  send over TCP.
- If LAN discovery fails or the socket errors, send over the relay.
- Sending over both is harmless — the Mac dedupes on `id`.
