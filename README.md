# OFFGRID

> **Internet-Resilient Digital Ecosystem**  
> A software-defined decentralized networking and offline-first synchronization system.

---

## 1. System Overview

OFFGRID is designed to ensure digital communications, emergency alerts, critical data capture, and collaborative coordination continue uninterrupted during internet outages, natural disasters, or remote off-grid operations.

### Core Objectives
1. **Zero-Internet Operation:** Applications operate completely offline using local persistence.
2. **Local-First Writes:** Every operation is saved locally to SQLite/Room before any network transmission.
3. **Peer-to-Peer Mesh:** Nearby devices discover each other automatically via Multipeer Connectivity (iOS) and BLE GATT (cross-platform).
4. **Store-and-Forward Relay:** Intermediate nodes can carry and relay encrypted packets between disconnected nodes.
5. **Gateway Synchronization:** When an internet-connected gateway node is discovered, operations synchronize to the central cloud backend.
6. **Idempotence & Deduplication:** Operation IDs and vector clocks prevent duplicate state execution.
7. **Conflict Detection:** Concurrent edits are detected and flagged using deterministic causal ordering.

---

## 2. Monorepo Structure

```
OFFGRID/
│
├── apps/
│   ├── web-dashboard/        # React + Vite + TypeScript web dashboard (Engineer 1)
│   ├── android/              # Native Kotlin + Jetpack Compose Android app (Engineer 2)
│   └── ios/                  # Native Swift + SwiftUI iOS app (Engineer 3)
│
├── services/
│   ├── api-server/           # Node.js + Express REST & WebSocket API (Engineer 1)
│   ├── network-node/         # Central routing and relay node (Engineer 1)
│   └── sync-engine/          # Cloud conflict resolution & sync service (Engineer 1)
│
├── packages/
│   ├── protocol/             # Canonical packet framing, envelopes, serialization (Lead: Eng 1)
│   ├── shared-types/         # Cross-platform TypeScript interfaces and schemas
│   └── routing/              # Routing logic, metric calculation, hop control
│
├── database/
│   ├── migrations/           # PostgreSQL relational schema migrations
│   └── seeds/                # Demo and test seed data
│
├── docs/
│   ├── architecture.md       # High-level architecture and data flows
│   ├── protocol.md           # Wire protocol, byte layouts, MTU handling
│   ├── api-contract.md       # REST endpoints & WebSocket RPC schema
│   ├── sync-rules.md         # Causal ordering, deduplication & conflict resolution
│   ├── development-setup.md  # Detailed setup guide for each engineer
│   └── team-responsibilities.md # Clear ownership and demarcation boundaries
│
├── scripts/                  # Workspace utility scripts
├── .github/                  # PR templates and GitHub workflows
├── .editorconfig             # Shared code formatting across IDEs
├── .gitignore                # Comprehensive multi-stack ignore rules
├── package.json              # Monorepo root manifest
└── pnpm-workspace.yaml       # pnpm workspace configuration
```

---

## 3. Team Responsibilities

| Role | Engineer | Focus Area | Technology Stack |
| :--- | :--- | :--- | :--- |
| **Lead / Infra** | **Engineer 1** | Web Dashboard, Backend API, Sync Engine, Shared Protocol | Node.js, Express, React, Vite, PostgreSQL, TypeScript |
| **Android** | **Engineer 2** | Native Android Application, BLE GATT, Local DB | Kotlin, Jetpack Compose, Room, BLE, Coroutines |
| **iOS (Me)** | **Engineer 3** | Monorepo Setup, Native iOS Application, Offline Storage, iOS Discovery | Swift, SwiftUI, SQLite, Multipeer Connectivity, CoreBluetooth |

---

## 4. Quick Start

### Prerequisites
- **Node.js**: `v20.x` or higher
- **pnpm**: `v10.x` or `v12.x` (`corepack enable` or `npm install -g pnpm`)
- **Xcode**: `16.x` or higher (for iOS)
- **Android Studio**: Ladybug / Meerkat with Android SDK 34+ (for Android)

### Install Node/TypeScript Dependencies
```bash
pnpm install
```

### Run Web & Backend (Engineer 1)
```bash
# Start backend API
pnpm --filter @offgrid/api-server dev

# Start Web Dashboard
pnpm --filter @offgrid/web-dashboard dev
```

### Run iOS Application (Engineer 3)
```bash
cd apps/ios
open OFFGRID.xcodeproj
# Or build via command line:
xcodebuild -project OFFGRID.xcodeproj -scheme OFFGRID -destination 'generic/platform=iOS Simulator' build
```

### Run Android Application (Engineer 2)
```bash
cd apps/android
./gradlew assembleDebug
```

---

## 5. Branching & Contribution
See [CONTRIBUTING.md](./CONTRIBUTING.md) and [docs/development-setup.md](./docs/development-setup.md) for full instructions.
