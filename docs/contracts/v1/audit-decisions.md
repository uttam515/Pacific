# iOS audit decisions — 1.0.0-rc.2 (review candidate)

This updates PR #3 before freeze. These are concrete proposals for both mobile owners to approve. No native runtime is modified. The iOS team's reported passing outbox, duplicate suppression, and restart-recovery components must be retained; change their serializers/adapters through explicit migrations and regression-test them. The reported physical iOS chat/SOS baseline must be repeated afterward.

## A. BLE: smaller messages, one minimal common frame

The general IP/Multipeer envelope ceiling stays 65536 encoded UTF-8 bytes. **BLE MVP maximum is 2048 encoded envelope bytes, including all JSON headers and payload.** It is a maximum, not a target payload. UTF-8 bytes and characters are different: check the FINAL serialized byte count. An over-limit operation stays durably queued; try a compatible local-IP/Multipeer or backend route when available. Surface BLE_SIZE_LIMIT locally. Never truncate content, mark it sent, or claim the data crossed BLE.

A small JSON operation can still exceed an individual GATT write. Therefore a payload cap alone does not remove the need for shared framing. Use this deliberately conservative fixed frame while proving interoperability; adaptive MTU packing, selective retry, compression and large BLE messages are deferred. The choice is a review default, not a measured performance claim.

Every GATT characteristic write/notification carries ONE frame of 13..20 bytes:

| Byte offset | Size | Encoding / value |
| --- | --- | --- |
| 0 | 2 | ASCII OG, hex 4f47 |
| 2 | 1 | framing version 1 (independent of JSON protocol version) |
| 3 | 1 | reserved flags, MUST be 0 |
| 4 | 4 | unsigned transferId, big-endian, 1..4294967295 |
| 8 | 2 | unsigned zero-based chunkIndex, big-endian |
| 10 | 2 | unsigned chunkCount, big-endian, 1..256 |
| 12 | 1..8 | raw UTF-8 envelope bytes, split BEFORE decoding text |

Use exactly 8 data bytes per non-final frame; final frame is 1..8 bytes. chunkCount=ceil(byteLength/8). No text/hex/base64 wrapping on the characteristic. Fixture hex is only a representation for tests. Runtime must report a supported value length >=20 in that direction; otherwise this profile is unavailable. Both sides must explicitly select this profile; never infer it from characteristic UUIDs or mix it with legacy raw JSON on the same characteristic. Unknown framing version is an incompatibility, not permission to interpret raw bytes.

Sender uses increasing transferIds within each connection/direction; never reuse them, including retries. A whole-transfer retry has a NEW transferId, while preserving packetId/operationId according to their existing semantics. On exhaustion reconnect and create a fresh session. Receiver is scoped by connection/direction, not by unauthenticated JSON node name. One outgoing and one incoming transfer per connection at a time. Disconnect discards incomplete buffers; durable operations/outbox remain.

Receiver accepts reordered chunks and byte-identical duplicates. A conflicting duplicate or changed chunkCount aborts and retires the transfer. Reject out-of-range index/count, malformed lengths, or payloads above the cap before growing buffers. Ignore/reject frames from already retired transfer IDs. A different transfer ID while one is active returns local TRANSFER_BUSY; it does not evict the in-flight operation. Limits: 15 seconds without a NEW chunk, 120 seconds total from first chunk; these are proposed test defaults. Identical duplicate chunks do not reset the idle timer. On timeout discard/retire the incomplete buffer; sender retries a new transfer. Timers run even when no new frame arrives (the reference implementation checks deadlines when accept is called; native adapters need a cleanup timer).

After all chunks: concatenate bytes, decode UTF-8 strictly, parse JSON, check schema and semantic limits, then persist. Emit PEER_STORED only after the complete operation is durable. A characteristic write response proves only that a frame write completed; it is not an operation ACK. ACK envelopes use the same framing, but never generate an ACK-of-ACK. Pacing: writes with response wait for the platform completion callback; notification sends obey native queue/backpressure readiness. No new custom per-fragment ACK/retry protocol in MVP. Missing chunks lead to whole-transfer timeout/retry.

`packages/protocol/reference/ble-v1.mjs` is a platform-neutral Node test reference, not a native transport implementation. `packages/protocol/fixtures/ble-v1/golden.json` supplies exact expected bytes and reconstruction. Physical iOS↔Android tests must verify write/notification capacity, backpressure, reordering/loss, reassembly and ACK timing. Existing iOS Multipeer sessions need not use BLE framing; preserve their reliable transport.

## B. Broadcast: per-hop storage, explicit application acknowledgment

For SYNC_OP with destinationNodeId="*":

- Each directly receiving peer that validates and durably stores the operation MAY return one PEER_STORED acknowledgment over the direct authenticated session to the immediate sender. It must be unicast; never broadcast an ACK. Its acknowledgingNodeId is that peer; packetId refers to the received envelope. Preserve a stable ackId for retries of the same peer/operation receipt.
- Receipt from a duplicate packet can repeat that same storage ACK to recover a lost response. Avoid proactive repeated ACKs or flooding ACKs through the mesh.
- An ordinary receiver does NOT automatically emit RECIPIENT_ACKNOWLEDGED. That stage requires an explicit authorized user/responder action (e.g., acknowledge an SOS). It is submitted once per responder/operation with its own stable ackId. Multiple responders can acknowledge independently; retain every authorized receipt.
- Send the application receipt to the originating node through a reachable unicast route or queue it for backend /receipts upload. Do not broadcast it. Response arrival still depends on actual connectivity and authorization.
- Backend commitment remains one idempotent effect per operation, regardless of the number of peers/responders or gateways that submit it.

There is no “all recipients delivered” state for broadcast and no quorum. The population is unknown. The UI can show `peerStoredCount`/`responderCount` derived from distinct authorized receipt identities, backend committed, and last observed evidence. A count of one is never labeled delivered to everyone. A broadcast announcement simply being displayed is not an explicit recipient acknowledgment.

## C. iOS identity: defaults may mirror; non-restored marker is authoritative

A UserDefaults marker can help detect a simple delete/reinstall on a test device, but it is not sufficient as the sole source for the previously agreed restore/migration policy: Apple documents that persistent defaults are backed up. Use an app-private durable installation-marker file EXCLUDED from backup as the authoritative lifecycle marker. UserDefaults may mirror its nodeId for convenience, never override it. Store credentials in Keychain bound to that marker's nodeId; a stale Keychain nodeId/credential alone is not an installation identity.

On launch, serialize identity initialization before any operation creation:

1. Valid marker and matching existing node identity: reuse it; app restart/update must not change nodeId or existing outbox.
2. Marker absent AND no existing local node/outbox: generate a random UUIDv4, atomically persist marker/identity, discard stale unmatched credentials, then provision the new identity.
3. Marker absent BUT prototype local data already exists: do not silently clear or rewrite the working outbox. First display/require explicit migration review. For this known test-install upgrade, the owner may approve adopting its existing nodeId into a new excluded marker without altering any old operations. Confirm with the operator/backend that it is not a cloned identity. Record that decision. This is a controlled one-time prototype migration, not a general reinstall heuristic.
4. Marker/Keychain mismatch, restored data without marker, deletion/reinstall, or another device: require explicit identity/recovery review. A genuinely new installation gets a NEW nodeId and new provisioning; preserve old audit and recovered operations' original IDs. Never infer which case occurred from UserDefaults alone. Recovered outbox cannot be uploaded under a different origin without an authorized recovery path.

Missing/corrupt marker alone cannot distinguish a prototype upgrade from a restore. When ambiguous, pause identity migration and preserve data rather than silently creating a cloned identity or destroying operations. App offload that preserves app data/marker retains identity. Do not promise unsynchronized data survives deletion. iOS owner must implement backup exclusion and run upgrade/reinstall/restore tests; Android implements equivalent marker/provisioning policy.

Apple references: https://developer.apple.com/documentation/foundation/userdefaults and https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:).

## D. Announcements: model/persistence yes, mobile UI no

MESSAGE CREATE and SOS CREATE are the mobile UX MVP. ANNOUNCEMENT CREATE/UPDATE remain in the shared schema for the conflict demo; the dashboard/backend can provide the editing and conflict-resolution UI. Mobile clients must decode, validate, persist and sync announcements losslessly through the generic operation/outbox machinery. They do NOT need an announcement editor or conflict-resolution screen before the first iPhone→backend demo. Native UI can show a basic read-only message/status or defer rendering, but must not discard valid operation records or claim a conflicted edit was committed.

Scope first milestone: existing persistent iOS message/SOS → optional VERIFIED peer/gateway path → backend commit → dashboard visibility → retry of same immutable operation ID without duplicate effects. Backend endpoints are still pending implementation. No native transport or backend behavior is proved by these fixtures.

## E. Fixture audit scoring and migration order

The original manifest has 33 examples: 26 expected-valid and 7 expected-invalid. A fixture test PASSES when actual validation matches manifest.valid. Expected-invalid fixtures must be rejected, not decoded successfully. Report `valid accepted / 26`, `invalid rejected / 7`, and round-trip semantic mismatches separately. Do not require all 33 to decode. Use equivalent typed validation on each platform; Codable accepting a shape without rejecting a missing/unknown field is not full contract validation.

BLE golden vectors are a separate test collection and do not alter the 33-example schema manifest. Update its release marker to rc.2; JSON field names/wire version remain unchanged from rc.1.

Incremental iOS migration: (1) models and strict fixture outcomes, (2) lossless persistence serializer migration with existing outbox/dedup/restart tests, (3) envelope and receipt mapping, (4) transport reassembly and physical regression tests where BLE is enabled, (5) real backend sync. Run existing two-iPhone message/SOS checks at each step. Freeze only after both mobile owners review these four decisions; no auto-merge or claimed sign-off.
