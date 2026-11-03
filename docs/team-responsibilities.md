# OFFGRID Team Responsibilities & Ownership Matrix

---

## 1. Primary Ownership Breakdown

### Engineer 1 — Web Dashboard, Backend & Infrastructure Lead
- **Primary Directories:**
  - `apps/web-dashboard/`
  - `services/api-server/`
  - `services/network-node/`
  - `services/sync-engine/`
  - `packages/protocol/` (Lead Architect)
  - `packages/shared-types/`
  - `database/migrations/`
  - `database/seeds/`
- **Ownership Scope:**
  - Canonical packet framing and serialization formats.
  - REST & WebSocket API contracts.
  - Central conflict resolution rules.
  - PostgreSQL schema and database persistence.
  - Web dashboard visualization for network topology, SOS alerts, and sync state.

---

### Engineer 2 — Android Developer
- **Primary Directories:**
  - `apps/android/`
- **Ownership Scope:**
  - Native Android app using Kotlin & Jetpack Compose.
  - Room local database implementation conforming to offline-first rules.
  - Android BLE peripheral & central implementation (GATT server/client).
  - Wi-Fi Aware / direct communication where applicable.
  - Android packet handling, store-and-forward relay, and gateway synchronization.

---

### Engineer 3 — iOS Developer (Me)
- **Primary Directories:**
  - `apps/ios/`
  - Repository setup, monorepo maintenance, Git configuration.
- **Ownership Scope:**
  - Native iOS app using Swift & SwiftUI (MVVM architecture).
  - SQLite local database persistence (`SQLiteDatabase` engine).
  - Apple Multipeer Connectivity for zero-configuration iOS mesh.
  - CoreBluetooth BLE manager for cross-platform Android interoperability.
  - Local operation queue and synchronization engine client.
  - Home Dashboard, Offline Chat, SOS, Announcements, and Network Status views.

---

## 2. Cross-Cutting Collaboration Rules

1. **Protocol Changes:** Mobile engineers (Eng 2 & 3) do NOT alter wire packet definitions without Engineer 1's review and sign-off.
2. **Cross-Platform BLE:** Engineer 2 and Engineer 3 must test BLE GATT compatibility using the shared UUIDs defined in `docs/protocol.md`.
3. **No Hidden State:** Every operation sent over the wire MUST be inspectable in SQLite and Room.
