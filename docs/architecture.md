# OFFGRID System Architecture

> Internet-Resilient Digital Ecosystem Architecture Specification

---

## 1. System Philosophy

Traditional applications assume continuous, low-latency cloud connectivity. OFFGRID reverses this paradigm:
1. **Local-First As Truth:** Local device storage (SQLite on iOS, Room on Android) is the immediate source of truth. Every user write is locally persisted before any network call.
2. **Opportunistic Dissemination:** Devices form ad-hoc peer networks whenever other OFFGRID nodes are within physical proximity (via Multipeer Connectivity and Bluetooth Low Energy).
3. **Store-and-Forward Routing:** Packets carry hop limits and time-to-live (TTL) counters, enabling intermediate nodes to relay packets to intended recipients.
4. **Gateway Convergence:** When any node establishes internet reachability, it acts as a gateway, uploading pending synchronization operations to the central backend.

---

## 2. Component Hierarchy

```
+-----------------------------------------------------------------------------------+
|                                  OFFGRID HUB                                      |
|  (User-Facing Modules: Offline Chat | Emergency SOS | Files | Network Dashboard)  |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                                 OFFGRID CORE                                      |
|                                                                                   |
|  +------------------------+  +--------------------------+  +-------------------+  |
|  |     Operation Queue    |  |       Sync Engine        |  |  Security / Auth  |  |
|  | (Deterministic SQLite) |  | (Lamport / Vector Clock) |  | (Node Signatures) |  |
|  +------------------------+  +--------------------------+  +-------------------+  |
|                                        |                                          |
|                                        v                                          |
|  +-----------------------------------------------------------------------------+  |
|  |                        Transport Coordinator Router                         |  |
|  +-----------------------------------------------------------------------------+  |
|          |                                   |                             |      |
|          v                                   v                             v      |
|  +---------------+                 +--------------------+        +-------------+  |
|  |  Multipeer    |                 |   CoreBluetooth    |        | WebSocket / |  |
|  |  Connectivity |                 |   BLE GATT         |        | HTTP Cloud  |  |
|  |  (iOS <-> iOS)|                 | (Cross-Platform)   |        | (Gateway)   |  |
|  +---------------+                 +--------------------+        +-------------+  |
+-----------------------------------------------------------------------------------+
```

---

## 3. Node Types and Topologies

1. **Edge Client Nodes (iOS / Android Devices):**
   - Run native apps with SQLite/Room storage.
   - Advertise and discover peers over BLE and Wi-Fi Multipeer.
   - Exchange messages, emergency alerts, and sync tokens.

2. **Relay Nodes:**
   - Client or stationary nodes configured to store and forward encrypted transit packets.
   - Do not require decrypted access to end-to-end payloads.

3. **Gateway Nodes:**
   - Any node that detects an active WAN/Internet interface.
   - Buffers operations and synchronizes bi-directionally with the central API server.

4. **Central Cloud Infrastructure (Engineer 1):**
   - Node.js/Express API server + PostgreSQL database.
   - Central conflict arbitrator, global audit log, and Web Dashboard.

---

## 4. Operation Lifecycle

```
[User Action]
      │
      ▼
[1. Generate UUID & Timestamp]
      │
      ▼
[2. SQLite ACID Commit] ──────────► [UI Updates Instantly]
      │
      ▼
[3. Enqueue to OperationQueue]
      │
      ├───────────────────────────────┬───────────────────────────────┐
      ▼                               ▼                               ▼
[Multipeer Direct Peer]       [BLE Cross-Platform Peer]       [Cloud Gateway Sync]
      │                               │                               │
      ▼                               ▼                               ▼
[Peer Ack Received]           [Peer Ack Received]             [Cloud Ack Received]
      │                               │                               │
      └───────────────────────────────┴───────────────────────────────┘
                                      │
                                      ▼
                        [Update Status in SQLite to SYNCED]
```
