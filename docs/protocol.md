> **Contract review update:** [v1 candidate](contracts/v1/README.md) supersedes the draft definitions below for review. Neither these drafts nor the candidate are implemented backend APIs. Freeze requires all three engineers' approval.

# OFFGRID Wire Protocol Specification

> **Owner:** Engineer 1 (Web, Backend & Infrastructure Lead)  
> **Status:** Draft / Initial Framing for Mobile Integration  
> **Mobile Implementers:** Engineer 2 (Android), Engineer 3 (iOS)

---

## 1. Design Constraints

- **Cross-Platform Interoperability:** Packets must be serialized identically across Swift, Kotlin, and TypeScript.
- **MTU Efficiency:** Bluetooth Low Energy MTUs range between 23 and 512 bytes. Packets must either fit within compact frames or support lightweight chunking.
- **Self-Contained Routing:** Headers contain destination address, source address, TTL, hop count, and signature without requiring connection-oriented handshakes.

---

## 2. Canonical Packet Envelope (JSON / Binary Equivalence)

Engineer 1 owns the binary or JSON wire encoding. For initial staging, JSON encoding is used:

```json
{
  "version": 1,
  "packetId": "UUIDv4-STRING",
  "type": "MESSAGE | SOS | ACK | SYNC_REQUEST | SYNC_RESPONSE | ANNOUNCEMENT",
  "sourceNodeId": "NODE-PUBKEY-OR-UUID",
  "destinationNodeId": "NODE-PUBKEY-OR-BROADCAST",
  "timestamp": 1730650000000,
  "ttl": 5,
  "hopCount": 0,
  "payload": { ... },
  "signature": "OPTIONAL-ECDSA-OR-ED25519-SIGNATURE"
}
```

---

## 3. Core Message Types

| Message Type | Purpose | Broadcast? | Priority |
| :--- | :--- | :--- | :--- |
| `SOS` | Critical life-safety emergency alert | Yes (`*`) | High (immediate relay) |
| `MESSAGE` | Direct or channel offline text chat | Direct / Group | Normal |
| `ACK` | Transport-level or application-level receipt | Direct | Low |
| `ANNOUNCEMENT` | Public bulletin or shelter status | Yes (`*`) | Normal |
| `SYNC_OP` | State machine operation sync record | Gateway/Direct | Normal |

---

## 4. Cross-Platform BLE GATT Specification

To bridge Android and iOS without relying on Apple-only Multipeer Connectivity:

- **Service UUID:** `7B6E0001-C72B-4E36-96F1-30AA4B848694`
- **TX Characteristic (Write / Write Without Response):** `7B6E0002-C72B-4E36-96F1-30AA4B848694`
- **RX Characteristic (Notify / Indicate):** `7B6E0003-C72B-4E36-96F1-30AA4B848694`

*Note: Engineer 1 will formalize the canonical binary serialization scheme.*
