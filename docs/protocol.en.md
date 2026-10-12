# Bluetooth Protocol

[简体中文](protocol.md) · English

MideaBar talks to Midea / Hualing air conditioners directly over Bluetooth Low Energy — no pairing, no account, no phone app. This document describes the protocol the app actually uses:

- The byte layer (frames, encryption, handshake, appliance frames) lives in [`Sources/MideaProtocol`](../Sources/MideaProtocol). It is pure code with no Bluetooth dependency and is unit-tested (`make test`).
- Bluetooth and timing (scanning, connecting, retries, reconnecting) live in [`Sources/MideaBar/ACLink.swift`](../Sources/MideaBar/ACLink.swift).

The protocol comes from public research into device behavior, with [midea-ble-go](https://github.com/midea-ble/midea-ble-go) as a reference; the conformance vectors in the unit tests were generated from its output.

## 1. Discovery

The AC continuously advertises manufacturer data with company ID `0x06A8`. Without the 2-byte company ID:

```
01 | SN (14 ASCII bytes) | 01 03 00 32 | MAC (6 bytes) | 00
```

Advertisements can arrive split across packets; the MAC is available only **once a complete packet of ≥25 bytes is received**. macOS doesn't expose the device's real MAC, so the identifier needed for the handshake has to be rebuilt from here:

```
advertisData = 0xAC ‖ first 8 bytes of SN ‖ MAC (reversed)     15 bytes
```

The app scans for 8 seconds: it connects immediately if it sees the SN it connected to last time, otherwise it picks the strongest signal.

## 2. GATT

| Item | UUID | Notes |
|---|---|---|
| Service | `FFA0` | |
| Write characteristic | `FFA1` | **Write-with-response only**; writes without response are silently dropped |
| Notify characteristic | `FFA2` | Replies may be fragmented or coalesced; reassemble by the `AA 55` header and length |

## 3. Three frame layers

Outgoing: appliance frame → business layer → security layer (encrypted) → connection layer → write to `FFA1`. Incoming is the reverse.

| Layer | Format | Checksum |
|---|---|---|
| Connection | `AA 55 LEN SEQ TYPE body CHK`, `LEN = body + 4` | `CHK = -Σ(LEN..body) & 0xFF` |
| Security | `CMD SEQ LEN body` | None — the AES-CCM tag provides integrity |
| Business | `TYPE LEN 00 body CHK`, `TYPE` is always `0x20` | `CHK = -Σ(TYPE..body) & 0xFF` |

- Connection `TYPE`: `02` = handshake frame encrypted with rootKey, `03` = business frame encrypted with sessionKey.
- Security `CMD`: `01`–`03` are handshake steps c1–c3, `04` is business.
- The two `SEQ` counters are independent, start at a random 1–255, and increment per frame (skipping 0).
- A connection-layer body shorter than 16 bytes isn't ciphertext but a device error code, e.g. `ff04` (security layer failure) or `ff05` (counter error).

## 4. Keys and encryption

```
rootKey    = HKDF-SHA256(ikm = advertisData, salt = empty, info = "midea_bleapp"), 16 bytes
sessionKey = SHA-256(X coordinate of the P-256 ECDH shared point), first 16 bytes
```

Public keys are 64 bytes `X ‖ Y` (without the `0x04` prefix).

Encryption is **AES-128-CCM** with an 8-byte random nonce, an 8-byte tag and no associated data; the format is `nonce ‖ ciphertext ‖ tag`. CryptoKit has no CCM, so the app implements it per RFC 3610 by combining CBC-MAC and CTR on top of the AES block cipher.

## 5. Handshake

```
App                                                     AC
 │  c1: 6-byte random openId (rootKey)                    │
 │ ──────────────────────────────────────────────────────→│
 │←────────────────────────────────────────── c1 reply     │
 │  c2: empty (rootKey)                                    │
 │ ──────────────────────────────────────────────────────→│
 │←──────────────────── c2 reply: device ephemeral key     │
 │  generate a P-256 key pair, derive sessionKey           │
 │  c3: our public key ‖ advertisData sealed w/ sessionKey │
 │ ──────────────────────────────────────────────────────→│
 │←──────────────────── c3 reply: 1 success / 0 failure    │
 │  business frames (sessionKey) …                         │
```

Timing:

- **Keep sending c1**: the device often ignores the first one or two c1 on a new connection. Send a brand-new frame (new seq, new nonce) every 1.5 s, up to 15 times.
- **Never compute c2 twice**: the device rotates its ephemeral key on every c2 it receives. In the c2 and c3 phases, resend the exact same frame every 1.2 s, up to 8 times, and send c3 as soon as the key arrives — the device disconnects a few seconds after c2.
- Every connection performs a full handshake; the whole handshake times out after 30 s.

## 6. Appliance frames

The business body is a standard Midea appliance frame (device type `0xAC`):

```
AA LEN AC 00 00 00 00 00 PROTO MSG OPCODE data… CRC8 SUM
```

- `CRC8`: CRC-8/MAXIM (reflected polynomial 0x8C) over the data starting at `OPCODE`.
- `SUM`: `-Σ(LEN..CRC8) & 0xFF`.

| Frame | OPCODE | Length |
|---|---|---|
| Control | `0x40` | 37 bytes, `PROTO=2 MSG=2` |
| Query | `0x41` | 24 bytes, `PROTO=0 MSG=3` |
| Status | `0xC0` | Reply, or pushed by the device |

### Control frame (0x40), main fields

| Byte | Field |
|---|---|
| 11 | bit0 power, bit1 control source (always 1), bit6 beep |
| 12 | bits 5-7 mode (1 auto 2 cool 3 dry 4 heat 5 fan), bits 0-3 integer temperature − 16, bit4 half degree |
| 13 | Fan: 40 low / 60 medium / 80 high / 100 max / 102 auto |
| 17 | Swing: base `0x30`, vertical `0x0C`, horizontal `0x03` |
| 18 | bit5 turbo |
| 19 | bit3 electric heat, bit7 eco |
| 28 | Second temperature: `(round(t×10 + 0.5) / 10 − 12) & 31` |
| 34 | Frame order, cycling 1–255 |

Unused fields (timers, sleep curve, …) are encoded with protocol defaults. **Control is read-modify-write**: load the device's current state, change the target field, then send the whole frame, so unchanged settings aren't clobbered.

### Status frame (0xC0), main fields

With `S = frame[10…]` (`S[0] = 0xC0`):

| Position | Field |
|---|---|
| S[1] | bit0 power, bit7 fault |
| S[2] | bits 5-7 mode, bits 0-3 integer temperature − 16, bit4 half degree |
| S[3] | Fan speed |
| S[7] | When the high nibble is `0x3`, the low nibble is swing (`0x0C` vertical, `0x03` horizontal) |
| S[8] | bit5 turbo |
| S[9] | bit3 electric heat, bit4 eco |
| S[11] / S[12] | Indoor / outdoor temperature `(x − 50) / 2`, decimals in the low / high nibble of S[15] |
| S[13] | Second temperature − 12 |

## 7. Commands

- Commands run serially; any status frame counts as the reply (the device also pushes status on its own).
- The device often drops the first frame and debounces consecutive frames for about 550 ms before replying. So the app resends after 0.15 s, then every second, up to 6 times; resends carry the same content with a new seq.
- With no reply, a lost connection or a failed handshake, the app disconnects and reconnects after 5 s.

## 8. Security

rootKey is derived entirely from public advertisements, so anyone nearby can compute it. The session key only protects against passive eavesdropping, not an active attacker impersonating one side during the handshake. In other words, someone within Bluetooth range (about ten meters) could control your AC. That's acceptable for home use, but worth knowing.
