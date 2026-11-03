# OFFGRID Synchronization & Conflict Resolution Rules

> **Lead Architect:** Engineer 1  
> **Client Implementers:** Engineer 2 (Android), Engineer 3 (iOS)

---

## 1. Core Principles

1. **Idempotence:** Every operation has a globally unique UUID. Applying an operation multiple times produces the exact same state as applying it once.
2. **Causal Ordering (Lamport Logical Clocks):**
   - Each node maintains a monotonically increasing integer clock `L`.
   - On local operation: `L = L + 1`.
   - On receiving an operation with clock `L_remote`: `L = max(L, L_remote) + 1`.
3. **Deterministic Tie-Breaking:**
   - If two operations on the same entity have the same logical clock, the tie is broken deterministically by string comparison of `nodeId` (`nodeId_A > nodeId_B`).
4. **Append-Only Operation Log:**
   - Instead of overwriting mutable entities directly, changes are logged as immutable operations (`OperationRecord`).
   - The material view is computed from the operation log.

---

## 2. Operation State Machine on Mobile Clients

```
[DRAFT / USER ACTION]
         │
         ▼
     [LOCAL] ─── Saved in SQLite (status: 'local', synced: 0)
         │
         ├──────────────────────────────────────────────┐
         ▼                                              ▼
[PEER_RELAYED] (Transmitted to mesh peer)      [GATEWAY_SYNCED] (Sent to API server)
         │                                              │
         ▼                                              ▼
(status: 'relayed')                            (status: 'synced', synced: 1)
```

---

## 3. Conflict Detection Scenarios

### Scenario A: Add-Wins Set (SOS Alerts & Chat Messages)
- Messages and SOS alerts are append-only. There are no destructive updates.
- If an operation ID is already present in the database, it is safely ignored as a duplicate.

### Scenario B: Concurrent Entity Edits (e.g., Announcement Text)
- When two nodes edit the same announcement while disconnected:
  1. Detect conflict: Both operations reference the same `parentVersionId` or overlapping clock ranges.
  2. Flag conflict: Store both versions locally with `isConflict = true`.
  3. Presentation: The UI displays both versions and allows user/admin resolution, or applies Last-Write-Wins (LWW) via Lamport timestamp.
