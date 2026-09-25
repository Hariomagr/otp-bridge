# OTP Bridge

Forward SMS (and any text messages) from one Android phone to one Mac,
end-to-end encrypted. Personal-use, single-pair. **LAN first, relay fallback.**

OTPs pop a native Mac notification with a **Copy code** button; every message
is searchable in a Mac menu-bar app. Nothing readable ever touches the server.

```
 Android phone                          Mac (menu bar)
 ┌────────────────┐                     ┌─────────────────────┐
 │ SmsReceiver    │   LAN: Bonjour +    │ NWListener (TCP)     │
 │  → OtpExtract  │──── TCP socket ────▶│   ┐                  │
 │  → Crypto      │                     │   ├─ decrypt (AES-   │
 │  → ForwardSvc  │   relay fallback    │   │   256-GCM)       │
 │ (LAN ∥ relay)  │──── WebSocket ─────▶│ RelayClient (WS)     │
 └────────────────┘         │           │   ┘  → dedupe on id  │
                            ▼            │   → notify (OTP only)│
                   ┌─────────────────┐   │   → clipboard        │
                   │ Cloudflare      │   │   → Messages window  │
                   │ Worker + DO     │   └─────────────────────┘
                   │ (ciphertext only)│
                   └─────────────────┘
```

The AES-256 key is generated on the Mac, shown as a QR, and scanned once by the
phone — it never crosses any network. The relay only ever sees ciphertext.

Wire format is in [PROTOCOL.md](PROTOCOL.md), verified byte-compatible across
Node, Swift (Mac), and Java (Android).

## Repo layout

| Dir             | What                                                    | Build with        |
|-----------------|---------------------------------------------------------|-------------------|
| `mac/`          | SwiftUI menu-bar app (animated mascot, Messages window) | `swiftc` (Xcode)  |
| `android/`      | Kotlin app (SMS capture + forward)                      | Android Studio    |
| `relay-worker/` | Relay on Cloudflare Workers + Durable Object (free)     | wrangler          |
| `relay/`        | Same relay in Node (local/LAN testing, Docker)          | Node ≥ 18         |

## Features

- **End-to-end encrypted** (AES-256-GCM); relay is zero-knowledge.
- **LAN + relay in parallel**; Mac dedupes on message id, so it's always the
  fastest path with a fallback when off Wi-Fi.
- **Mac menu-bar app**: animated mascot icon, notification with Copy action,
  auto-copy + 60s clipboard auto-clear.
- **Messages window** (email-style): searchable history, multi-select delete,
  clear-all. History persists locally.
- **Notifications for OTPs only**; all messages still land in the list.
- **QR pairing** via Google's ML Kit scanner (robust, portrait, no camera perm).
- **Reachability-aware**: the phone only offers "Send test OTP" when the Mac is
  reachable (LAN discoverable or present on the relay).
- **Relay controls on Mac**: lock the URL after setting, Change to edit, and
  Disable/Enable without losing the URL.
- **Call alerts + remote Accept/Reject**: incoming / missed calls show on the
  Mac with caller name (via the Android call-screening role for ring-time
  caller ID). Accept/Reject from the notification or the menu footer answer or
  end the call on the phone (`TelecomManager`). Reject/Accept use the relay as
  the Mac→phone reverse channel. (Two-way call audio isn't possible — Android
  blocks in-call audio capture for third-party apps.)

---

## Setup

### 1. Deploy the relay (Cloudflare Workers — free, no credit card)

Only needed for delivery when the phone and Mac aren't on the same Wi-Fi. For
LAN-only use, skip this and leave the relay field blank.

```bash
cd relay-worker
npm install
npx wrangler login                      # opens browser; no card asked
npx wrangler secret put AUTH_TOKEN      # paste: openssl rand -hex 16
npx wrangler deploy                     # prints https://otp-relay.<you>.workers.dev
```

> First deploy needs a `*.workers.dev` subdomain on your account — if you see
> error 10063, open **Workers & Pages** in the Cloudflare dashboard once to
> claim a subdomain, then re-run `deploy`.

Your relay URL (note `wss://` and the token):

```
wss://otp-relay.<your-subdomain>.workers.dev?token=<the-secret-you-set>
```

### 2. Build & run the Mac app

```bash
cd mac
./gen-icons.sh      # generates the shared app icon (once)
./build.sh          # compiles OTP Bridge.app and ad-hoc signs it
open "build/OTP Bridge.app"
```

A mascot icon appears in the menu bar. Click it:
1. Allow notifications when macOS prompts.
2. (Optional) **Change** next to Relay → paste your `wss://…?token=…` → **Set**.
3. **Show pairing QR**.

> Ad-hoc signed for personal use. To distribute, sign with a Developer ID cert
> and notarize.

### 3. Build & install the Android app

Open `android/` in Android Studio and Run on your phone, or from the CLI:

```bash
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

In the app:
1. **Grant SMS & notification permissions.**
2. **Disable battery optimization** (important on Samsung/Xiaomi/Oppo/Vivo so
   the SMS receiver isn't killed in the background).
3. **Enable caller ID (call screening)** — grants the call-screening role so the
   caller's number/name is available at ring time (optional; call alerts still
   work without it, just with less reliable caller ID).
4. **Pair with Mac (scan QR)** — scan the QR from the Mac app.
4. With the Mac app open you'll see **"Mac connected"** and a **Send a test
   OTP** button — tap it; a notification should appear on the Mac within a
   second or two.

> Personal sideload only. `RECEIVE_SMS` forwarding does not pass Google Play
> review — don't publish this build. A public app would use
> `NotificationListenerService` instead.

---

## Verifying the plumbing

```bash
# Relay fan-out (Node):
node relay/smoke-test.mjs

# Crypto interop — Node encrypts, Swift & Java decrypt to identical bytes:
cd mac && swiftc -swift-version 5 Sources/Crypto.swift tests/main.swift -o build/interop
javac -d android/build android/CryptoInterop.java
# (see git history / earlier commits for the one-liner that ties them together)
```

## Security notes

- The relay `AUTH_TOKEN` only gates *connections*; confidentiality comes from
  the E2E key that never leaves your two devices. Setting a token is still worth
  it to keep strangers from flooding your relay.
- Rotate the token any time: `npx wrangler secret put AUTH_TOKEN` (takes effect
  immediately, no redeploy), then update the Mac's relay field and re-scan the QR.
- History is stored unencrypted on the Mac in Application Support. Encrypting it
  at rest is a possible future improvement.
