# OFFGRID contract v1 — 1.0.0-rc.1

**Status: REVIEW CANDIDATE. Not frozen; not a running API.** Engineer 1, Engineer 2 (Android), and Engineer 3 (iOS) must review this PR before declaring a freeze. No mobile or backend implementation is changed by this contract PR. The existing dashboard has a compatibility summary, not the complete delivery-evidence UI.

## Authoritative files

- [JSON Schema](../../../packages/protocol/schemas/v1/contract.schema.json): Draft 2020-12; every `$defs` entry is independently selectable. `$id` uses the reserved example domain as an identifier; no fetch is needed.
- [Field reference](field-reference.md): exact types, required/optional properties, allowed values, and bounds.
- [Shared fixtures](../../../packages/protocol/fixtures/v1): deterministic positive/negative examples; `manifest.json` identifies the target `$defs` type and expected validity.
- [Examples](examples.md): transport, operation, acknowledgments, sync, conflicts, and dashboard JSON.
- [Acceptance scenarios](acceptance.md): tests the implementations must pass before an integration claim.

Wire version is integer `1`: `version` on the transport envelope; `schemaVersion` on operations, acknowledgments, and API documents. `1.0.0-rc.1` identifies this review revision, not an extra JSON field. Unknown properties are rejected. Before adoption, replace the old draft v1 models together on all clients; never silently mix the earlier draft with this candidate. There is no released, frozen v1 to preserve yet. After freeze, breaking changes require a new wire/API major version; pre-freeze candidate edits require fixture and review updates.

## 1. IDs, data, and clocks

All identifiers are lowercase UUIDv4 strings. Persist `nodeId` once per app installation before creating any operations. Names and radio/MCP peer identifiers are display/transport information, never canonical node identity. `operationId` identifies one immutable action. `entityId` identifies its target record. Retries preserve the entire operation, including origin, timestamp, clock, payload, and operation ID. An edited payload is a new operation.

`packetId` identifies one transport envelope and stays stable for link-level retries. Re-enveloping an operation for a new dissemination may create a new packet ID; operation ID remains unchanged. Relays preserve `sourceNodeId` (envelope creator) and `originNodeId` (action author); they do not impersonate the original node. The authenticated immediate sender is supplied by the transport session, not inferred from these JSON claims.

Payloads are JSON objects, not escaped JSON strings. SQLite may serialize them internally. MVP entities: immutable MESSAGE and SOS CREATE, and ANNOUNCEMENT CREATE/UPDATE. DELETE, files, arbitrary payloads, and generic binary framing are outside this candidate. IDs cannot be reused across entity types. Entity CREATE requires baseVersion 0; UPDATE requires a known server version >=1. Offline chains for an unsynchronized entity are deferred: keep new local content, then create one appropriate operation after learning its committed version, instead of inventing server versions.

All numeric timestamps are UTC epoch milliseconds. Integers are limited to 0..9007199254740991 across languages. Lamport: local action L=L+1; receiving clock r sets L=max(L,r)+1. Do not advance beyond the safe integer maximum. Clocks order events; entity versions detect stale edits. Never select a conflict winner based only on wall-clock time or a node-ID tie-break.

## 2. Transport and delivery evidence

Packet types in this narrow v1 are SYNC_OP and ACK. A SYNC_OP contains the complete Operation; an ACK contains an Acknowledgment. Direct MESSAGE/SOS packet types in the old draft are replaced by Operation.entityType. JSON is UTF-8. Maximum encoded envelope: 65536 bytes; receivers check byte size before parsing. The BLE/IP adapters must fragment and reassemble envelopes before JSON validation; this contract does not claim that a 64 KiB frame fits a BLE write. Fragmentation framing and retry timeouts remain a transport-adapter review gate, not a proven interoperability feature.

Initial ttl=5, hopCount=0. A forwarder may forward only with ttl>0; persist/deliver locally even at ttl=0, but never forward it further. Before forwarding: ttl-=1; hopCount+=1. Maximum initial budget is 8; ttl+hopCount must remain <=8. TTL limits hops, not elapsed time. A repeated packet is not forwarded again automatically; a repeated durable operation is not applied again. A stored duplicate may trigger a repeat receipt to recover from a lost ACK. Forwarding success requires the chosen transport result; it does not prove backend/recipient delivery.

Track independent evidence:

| Evidence | Meaning |
| --- | --- |
| localStoredAt | Local atomic entity/outbox transaction completed |
| queuedAt | Eligible for delivery; preserved after restart |
| PEER_STORED ack | The named peer durably stored the operation |
| relayAttempts[] | A forwarder attempted a next-hop send; SENT or FAILED |
| BACKEND_COMMITTED ack | Backend durably committed the operation and its effect, or a prior commit is being acknowledged again |
| RECIPIENT_ACKNOWLEDGED ack | Intended recipient/responder explicitly acknowledged the application event |
| lastAttemptError | Current attempt issue, with retryable flag; does not erase previous evidence |

ACK packetId is optional because backend REST commits may have no mesh packet. entityVersion is required for BACKEND_COMMITTED. Acknowledgments reference operationId; packet receipts may additionally reference packetId. ackId is stable across retries. Peer receipts are evidence only within the authenticated/trusted peer test environment. A caller cannot submit a BACKEND_COMMITTED receipt as proof; only the backend emits it. Cryptographic end-to-end provenance over untrusted relays is not implemented or guaranteed by this contract; production untrusted relay ingestion remains gated on that design.

## 3. Backend API

Base: `/api/v1`. JSON request/response bodies; `Content-Type: application/json`. These endpoints are requirements, not implemented routes.

| Method and path | Request | Success |
| --- | --- | --- |
| POST /sync/push | PushRequest | 200 PushResponse; one result per input, same order |
| GET /sync/pull?cursor=c0&limit=100 | Cursor string (default c0); limit 1..100 (default 100) | 200 PullResponse |
| POST /receipts | ReceiptRequest | 200 ReceiptResponse |
| GET /conflicts?cursor=c0&limit=100 | Authorized change-list cursor (default c0); limit 1..100 (default 100) | 200 ConflictList |
| GET /conflicts/{conflictId} | UUID path parameter | 200 Conflict |
| POST /conflicts/{conflictId}/resolve | ResolveRequest | 200 ResolveResponse |
| GET /dashboard/snapshot | No body | 200 DashboardSnapshot |
| GET /health | No credentials | 200 `{"schemaVersion":1,"status":"ok"}` |

Push results: COMMITTED means both log and effect are durable. duplicate=true returns the original entityVersion and stable backend ack, never re-applies an effect. CONFLICT means competing content is durably preserved but NOT applied as the current entity; it includes conflictId and no commitment ACK. A retried conflicted action repeats its conflict result. REJECTED includes a machine code and retryable flag. Same operationId with different normalized fields is ID_REUSE, never accepted. Compare parsed typed fields, not JSON key order. Check idempotency before version checks, so a successful CREATE retry is not mistaken for an existing-entity conflict.

For POST /receipts, require body.nodeId and ack.acknowledgingNodeId to match the authenticated node. Accept only PEER_STORED or RECIPIENT_ACKNOWLEDGED, verify the node is an authorized peer/recipient/responder, and reject client-supplied BACKEND_COMMITTED. If the referenced operation is not known yet, return 404 ENTITY_NOT_FOUND with retryable=true; upload the operation first and retain/retry its receipt. Idempotence by ackId persists across server restarts.

Process each operation atomically; batches allow partial success. Duplicate IDs within one batch follow the same sequential idempotency rules. Invalid outer JSON/version/shape returns 400 or 422 ErrorResponse for the entire batch with no effects; schema-valid inputs can return semantic per-operation rejections. Max HTTP JSON body 1048576 bytes; oversized body returns 413. HTTP 401/403: no authenticated effects. 429/503 are transient and retryable. Reject permanent errors visibly; do not loop forever on invalid data. Requests that time out have unknown outcomes: retain operations and retry the same IDs. Never delete pending data merely because a request failed.

### Authentication and actual iPhone connectivity

Mobile MVP: provision a separate high-entropy bearer credential for each installation using out-of-band operator configuration. Backend maps that token to its registered nodeId and roles; request.nodeId must match the authenticated installation. No anonymous self-registration endpoint is specified. Never commit real tokens, use fixture identifiers as credentials, or place keys in URLs. Credentials must be revocable and stored in platform secure storage. Relayed originNodeIds may differ from the uploading gateway only where the operator has explicitly provisioned the gateway for the trusted test group. This grants no untrusted-public-mesh authenticity claim.

Dashboard: authenticated same-origin operator session via Secure/HttpOnly cookie over HTTPS. The dashboard adapter already uses credentials:include. Cross-origin deployment needs explicit credentialed CORS and session policy. Apply Origin/CSRF checks to mutations and WebSocket upgrades. Per-node bearer tokens are never embedded in the browser bundle. Operator conflict resolution requires an operator role and a resolver node bound to the authenticated operator. Acknowledging an SOS in the dashboard must create an application receipt so mobile clients learn it.

Use the computer's reachable LAN IP/hostname from a physical iPhone; `localhost` on an iPhone means that iPhone. HTTPS is the integration target. Any development HTTP exception, iOS ATS permission, local-network permission, firewall configuration, and physical-device reachability must be intentionally configured and tested by the platform owner; a repository contract does not configure them.

### Pull cursor and reconnect

A server commit-ordered change log includes committed operations, conflict changes/resolutions, and application receipts. Cursor is an opaque string (`c` followed by decimal digits in this v1), not a Lamport clock, timestamp, or entity version. Clients must not parse or manufacture it beyond bootstrap `c0`. Pagination has a stable server-defined ordering. nextCursor is the last SCANNED position, including invisible entries; an empty page may advance. hasMore=true means continue before waiting for another notification. Append and entity/log effects must be atomic so a late upload gets a new later sequence and cannot fall behind the cursor.

Persist received changes and nextCursor in one local transaction. On crash, replay from the previous cursor; deduplicate by operationId/ackId and conflict revision. The server applies authorization filters. Version-1 demo retains its whole change log: no normal cursor expiry. If retention is introduced, return 410 CURSOR_EXPIRED and require an explicit full-state bootstrap contract before enabling retention; never silently skip missing history. /conflicts uses the same append-only cursor model, scanning conflict-change records; returned entities are their current full versions. Resolved conflicts remain retrievable.

## 4. Conflicts and safe resolution

First valid CREATE commits entity version 1. A distinct CREATE that reuses an existing entityId is REJECTED VALIDATION_ERROR (not a duplicate operation). UPDATE for an unknown entity is REJECTED ENTITY_NOT_FOUND; retain it and fetch missing history before retrying. Each committed update increments the server entity version. Consider two different UPDATEs from baseVersion 1. The first received commits version 2. The second is saved as a conflict against that first branch; no last-write-wins replacement occurs. Conflict stores the competing operation objects, base version, current version, revision, and entity identity. Preserve the historical base and all operations in durable backend storage.

More concurrent candidates append to the OPEN conflict and increment its revision; later edits never disappear. While an entity has an OPEN conflict, further edits join that conflict and increment revision rather than silently changing the current entity. All affected clients retrieve it through /conflicts and CONFLICT_CHANGED pull entries. The dashboard's current two-column view can represent only two candidates; conflicts with more candidates must remain accessible through the full conflict API and block simplified dashboard resolution until a multi-candidate UI exists.

Resolve with a new operationId, selectedOperationId, expectedConflictRevision, and expectedEntityVersion. In one transaction: check operator permission, check version and revision, ensure selectedOperationId is a candidate, create an audited resolution record, commit the selected payload as NEW entity version 3, close the conflict, increment revision, append change-log records, and acknowledge the resolution operation. The operation log and both original candidates remain intact. The resolution record is a separate command type, not a client UPDATE with a forged base version. Return a COMMITTED_OPERATION change for its resulting canonical ANNOUNCEMENT UPDATE, using resolutionOperationId as operationId, authenticated resolverNodeId as origin, and the pre-resolution version as baseVersion. Do not ingest this backend-generated update again as an unrelated client change.

A repeated identical resolution ID returns its original response even when the conflict is now resolved. A different request against a closed conflict or stale revision/version returns 409 STALE_RESOLUTION with no effects; refetch before retry. Resolution IDs share the global mutation-ID namespace. Application receipt ackIds also have their own unique durable namespace and ID_REUSE protection. Snapshot-read and resolve race is handled by the two expected values, not by UI timing.

## 5. Dashboard notifications and disconnection

Use WebSockets at `/ws` for low-latency SYNC_NOTIFICATION, emitted ONLY after durable commit. The message contains a hint latestCursor, not authoritative entity state. Dashboard refetches /dashboard/snapshot; mobiles pull from their own saved cursor. Do not advance a cursor based on a notification or push response: that could skip unread updates. Notifications may be duplicated or lost.

Fallback: dashboard polls snapshots every 15 seconds. Reconnect the socket after 5 seconds; always refresh after reconnect/foreground/online recovery. A disconnected dashboard shows cached data with its ORIGINAL observedAt and a stale indicator. Never refresh timestamps for old observations. WebSockets are optional; SSE is not part of v1. Backend should debounce bursts, and clients coalesce simultaneous refreshes. Bound live snapshots to 100 recent operations/events and current relevant alerts/conflicts; pagination for larger inventories remains future work.

DashboardSnapshot retains the current schemaVersion and fields for compatibility, adding per-operation delivery evidence and conflict revision/candidate IDs. Summary status is presentation only: queued until evidence exists, relayed for durable peer evidence, synced only for backend commitment, conflict for unresolved candidate operations. Failed attempts appear in delivery.lastAttemptError and do not reset commitment. Never infer recipient acknowledgment from synced. Node lastSeen is independent of snapshot observedAt. A backend cannot observe an isolated device's localStoredAt/queuedAt until reported; omit those optional fields rather than invent them. Maps and topology are not proof of physical radio range.

`POST /dashboard/actions` is the existing separate operator-command adapter. Its ACK_ALERT action must create a durable recipient/responder receipt; acceptance means the operator command is stored, not that help has arrived. CREATE_ANNOUNCEMENT must produce a canonical operation. RETRY_SYNC acknowledges the retry request, not successful synchronization. Extend RESOLVE_CONFLICT actions with expectedConflictRevision, expectedEntityVersion, and selectedOperationId before enabling live resolution. The current frontend sends only a left/right choice and ID: backend must return a permanent validation error for that outdated resolution, and the frontend must be upgraded before live conflict resolution. No optimistic success is permitted.

## 6. Installation identity and reinstall

Generate a cryptographically random UUIDv4 on first launch when the installation identity record is absent. Store it in durable app-private storage; use it across normal restarts and app updates. Exclude the installation marker/node identity and bearer credential provisioning from device-to-device migration/backup restoration. If a restored database has no matching non-restored installation marker, generate a new nodeId and require new provisioning. Do not assume uninstall removes Keychain entries: a stale credential alone must never restore an installation identity.

After deletion/reinstall, loss of identity, cleared application data, or migration to another device: new installation nodeId and credential provisioning; backend retains old audit records under the old nodeId. No promise that unsynchronized data survives app deletion. An offload/update that preserves the marker retains the ID. A node name change never changes the UUID. Locally recovered operations keep original originNodeIds; import/recovery needs an explicit authorized recovery path, not silent reassignment. iOS/Android engineers own the platform-specific exclusion and lifecycle tests; this is the required policy rather than a claim of current implementation.

## 7. Review/freeze gate and reported physical evidence

Team report: Engineer 3 has installed OFFGRID on two physical iPhones and demonstrated discovery, connection, and message exchange. This is user-reported physical evidence; not independently rerun by Engineer 1. It does NOT establish multi-hop forwarding, durability/restart recovery, Android interoperability, background relay, backend sync, or this candidate schema's compatibility with those existing builds.

Freeze after: both mobile owners parse/encode the shared fixtures; Engineer 1 confirms backend validation and dashboard projection; delivery/ACK and conflict semantics reviewed; native framing and identity policy owners agree; versioned fixtures and schema checks pass. Record approvals in the PR. Commit/merge alone must not be described as a completed physical integration test.

## 8. Migration checklist from the existing draft

| Existing draft / implementation | Candidate change required before integration |
| --- | --- |
| OperationRecord.payloadJson / iOS upload of a JSON string | Decode local text to a JSON object in wire payload |
| OperationRecord lacks entityId/baseVersion | Add both; persist them in each local outbox record |
| push response acceptedIds/conflictedIds | Read results[] and its typed outcome; only COMMITTED updates backend-commit evidence |
| sinceClock integer | Persist opaque nextCursor, atomically with pulled data |
| MESSAGE/SOS wire packet types | Use SYNC_OP whose nested operation.entityType distinguishes the action |
| packet ACK without stage | Require typed stage; never infer backend commitment from peer storage |
| shared-types/protocol TypeScript exports | Still legacy draft in this PR; update/derive models during the coordinated implementation after review |
| dashboard RESOLVE_CONFLICT sends only left/right | Add candidate operation ID and both expected version guards before enabling live resolution |
| iOS default date serialization | Verify fixture round trips produce numeric epoch milliseconds, not platform-default dates or seconds |

Both mobile apps must first pass round-trip fixture tests, preserving all required fields, before switching peer exchange to this candidate. Do not claim that the existing physically tested iOS builds already use the candidate contract.
