# Implementation acceptance scenarios

Schema/fixture tests validate examples and internal consistency; they do not run the backend or prove physical networking. All steps below remain integration requirements.

## A. Physical iPhone → backend → dashboard

1. Provision node A with its own token and reachable HTTPS backend URL. Keep fixture credentials out of code. Start dashboard in live mode with an operator session.
2. Disconnect iPhone internet. Generate MESSAGE CREATE as in operation-message.json with fresh UUIDs. Save message and outbox atomically; stop/relaunch the app. Both must remain.
3. Restore a reachable route. POST sync-push-request.json shape. Assert one COMMITTED result with matching operationId, durable entityVersion, and BACKEND_COMMITTED ack.
4. Dashboard fetches dashboard-snapshot.json shape after SYNC_NOTIFICATION or within the next 15-second poll. Assert same operation ID, originNodeId, kind, synced status, and backend receipt. Recipient acknowledgment must still be absent unless explicitly generated.
5. Send exactly the same operation again, including after backend restart. Assert duplicate=true, same entity version/stable ACK, one entity effect, and no duplicate dashboard operation.
6. Submit the same operation ID with changed text. Assert ID_REUSE and no mutation.

## B. Lost acknowledgment / disconnected dashboard

Commit the operation then drop the HTTP response. Client must retain it, retry the same ID, and process duplicate commitment. Disconnect dashboard while creating more phone operations; it retains the last snapshot without updating observedAt. Reconnect with WebSocket unavailable; REST polling must catch up. Save pull changes and nextCursor together, crash/restart, and confirm no skipped/duplicated effects. Notification latestCursor must never directly update the client's pull cursor. Delay an old operation upload until after another client's cursor advances; it must receive a NEW sequence and be fetched later.

## C. Two offline announcement edits

Use announcement-create/edit-a/edit-b fixtures. After CREATE version 1, two offline clients independently UPDATE from base 1. First update commits v2; second returns CONFLICT and is preserved, not applied. Both clients retrieve conflict-open.json. Resolve with conflict-resolve-request.json; assert NEW v3, both candidates preserved, resolution receipt, and conflict revision increment. Retry same resolution ID and assert no v4. Send another resolution with stale guards or a different ID against the closed conflict; assert HTTP409 STALE_RESOLUTION. Send the same already-conflicted operation again; return its original conflict result without creating a new conflict. Third candidates must be preserved and simplified two-column dashboard resolution blocked.

## D. Receipt integrity and attempt failures

Persist a PEER_STORED receipt, then fail a relay attempt. Keep the receipt, local operation, and retryable failure. Do not mark backend-synced until backend commitment exists. Submit a forged backend receipt via POST /receipts; reject it. An authenticated intended recipient/responder can submit RECIPIENT_ACKNOWLEDGED; retrying the same ackId returns duplicate=true. Notifications/pull expose it without changing content. Enforce operation-specific recipient/group authorization.

## E. Identity and physical transport matrix

| Test | Required outcome / status |
| --- | --- |
| Two physical iPhones discover/connect/exchange current messages | Reported demonstrated by Engineer 3; repeat against upgraded contract |
| Restart / ordinary app update | Same node ID; outbox retained |
| Delete and reinstall / identity marker lost | New node ID and new provisioning; old server audit retained |
| Restored DB / device-to-device migration | No cloned active installation identity; explicit recovery required |
| iOS ↔ Android | Physical verification pending |
| A → B → C with A unable to reach C directly | Physical relay verification pending; evidence from actual forwarder |
| ttl=0 packet | May store/deliver locally; no forwarding |
| Repeated packet / operation | No forwarding loop; no repeated entity effect |
| BLE <=2048-byte envelope over fixed 20-byte frames | Golden frames, truncation/reorder/duplicate/timeout/backpressure behavior physically verified by mobile owners |
| App background/termination | Measure actual behavior; no permanent background-relay claim |

Record device models, OS versions, build SHA, transport, configuration, actual result, operation IDs, and time. Never include real bearer tokens in test reports.

## F. Broadcast, announcement and migration audit

Use audit-decisions.md: broadcast receivers emit no automatic RECIPIENT_ACKNOWLEDGED; peer receipts return unicast to the immediate sender, and ACKs are never rebroadcast or acknowledged recursively. Explicit authorized SOS responder actions yield independent application receipts; no all-peers-delivered state exists. Mobile announcement CREATE/UPDATE fixtures must round-trip through generic persistence/sync without requiring a new editor. For the prototype upgrade, preserve existing outbox operations and node IDs through an explicit one-time marker migration; deletion/restore ambiguity must never silently clone identity or discard data. Fixture score reports expected-valid accepted and expected-invalid rejected separately.
