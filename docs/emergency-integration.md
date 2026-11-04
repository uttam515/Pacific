# OFFGRID emergency integration — review branch

This is a development/sandbox emergency pipeline, not an operational emergency dispatch service. No external authority messages, calls, email, SMS, or webhooks are sent.

## Review and immutable baselines

- Integration branch: `feature/emergency-gateway-integration`, PR #5.
- iOS baseline: `a75ad5c23fd92374b9635eca95c03c949bafa3aa`.
- Backend foundation: `7567e2f066fc7e26ad00e75d87347afaafb3f6ed` (PR #4 stays draft).
- Contract rc.2 pin: `d321ccbf0166a78aa6c07d8803167ebe640d8e3d`.
- Contract schema/fixtures/ACK enums are unchanged. Emergency-management endpoints below are a separate additive HTTP surface with `schemaVersion: 1`; they are not mesh protocol changes or a contract freeze.
- Engineer 3 should pull this branch, review the gateway, SQLite and lifecycle changes, rebuild with Xcode, then run the physical acceptance worksheet. Neither source branch is overwritten or force-pushed.

## Hosting and credentials

Use an isolated clone to avoid disturbing existing work:

```sh
git clone --branch feature/emergency-gateway-integration https://github.com/uttam515/Pacific.git Pacific-integration
cd Pacific-integration
bash scripts/backend-macos.sh setup
```

The setup builds the frontend/backend, starts PostgreSQL, and executes all additive migrations. `node --env-file=.env.backend.local services/api-server/dist/cli.js status` must list `001_backend.sql`, `002_emergency_operations.sql`, and `003_gateway_events.sql`, with required tables verified. Windows PowerShell users can follow `backend-local-setup.md` using this integration branch and all migrations.

Obtain each phone's EXISTING installation UUID from OFFGRID → Sync → Internet gateway. Register A and B as `node` and C as `gateway`, all in the same response group. Every possible original sender must be registered; a gateway may relay only for registered nodes in its own group. Registration is a trusted host-admin action, not an open device enrollment API.

```sh
install -d -m 700 "$HOME/.offgrid"
# Replace with actual existing IDs; these variables do not create identities.
IOS_A='<existing A UUID>'
IOS_B='<existing B UUID>'
IOS_C='<existing C UUID>'
node --env-file=.env.backend.local services/api-server/dist/cli.js provision "$IOS_A" 'Sender A' node iOS local-demo --credential-file "$HOME/.offgrid/a.json"
node --env-file=.env.backend.local services/api-server/dist/cli.js provision "$IOS_B" 'Relay B' node iOS local-demo --credential-file "$HOME/.offgrid/b.json"
node --env-file=.env.backend.local services/api-server/dist/cli.js provision "$IOS_C" 'Gateway C' gateway iOS local-demo --credential-file "$HOME/.offgrid/c.json"
```

If C is already registered as a node, explicitly grant its capability first:

```sh
node --env-file=.env.backend.local services/api-server/dist/cli.js grant-gateway "$IOS_C"
```

This preserves its UUID and existing credentials and writes a host-administration audit event. It rejects unknown IDs and non-node roles. Never regenerate the phone's installation identity. Provision an independent operator UUID as in `backend-macos-setup.md`. Transfer C's credential directly into its SecureField using an approved private channel; never GitHub, chat, screenshots, logs or committed files. The app binds configuration to the existing local identity, stores it `WhenUnlockedThisDeviceOnly` in Keychain, and refuses configuration restored under a different node ID. The server stores only credential hashes. Original operations keep original origin/entity/operation IDs.

Run `bash scripts/backend-macos.sh start`. The printed LAN origin is a candidate until tested from a phone. Login at `http://<host>:4000/login`; the root page is the connected incident dashboard. Legacy network diagnostics remain at `/?legacy=1`; its previously gated commands remain gated. HTTP is permitted only by explicit trusted-local settings. Use HTTPS with a valid certificate for cellular/public access. Do not expose PostgreSQL or use broad firewall disabling.

**Cellular test distinction:** a private LAN IP normally cannot be reached over cellular. A same-Wi-Fi test verifies LAN integration, not the requested mobile-data gateway. For C using mobile data, host the API behind your team's authorized HTTPS reverse proxy and reachable hostname. Set C’s optional internet probe URL to a team-controlled public HTTPS endpoint serving exactly `OFFGRID_INTERNET_OK_V1` (the public `/api/v1/connectivity` path provides this). A LAN backend alone is not evidence of internet access. Without a probe, internet is explicitly unknown even if authenticated backend readiness succeeds. No such public host is deployed or implied by this branch. Keep `DASHBOARD_ORIGIN` equal to its exact HTTPS origin. `/ws` must be proxied with upgrade support. The browser UI uses same-origin cookies, not stored bearer tokens.

In C's Sync → Internet gateway screen, enter the API ORIGIN (no `/api/v1` path) and private credential. HTTPS is the default. For local-only tests, explicitly permit local HTTP; iOS ATS/local-network permissions may require a hostname ending `.local` and device permission. Do not enable arbitrary public HTTP loads. Use a Debug build on the controlled test mesh. Release defaults require explicit trusted peers and certificate validation. The unsigned rc.2 operation identifies an asserted origin. A trusted gateway is responsible for its relay assertion. Production device pairing/origin attestation requires separate review. Keep OFFGRID active on all test phones; the gateway pauses on inactive/background lifecycle. No continuous background availability claim is made.

## Transaction, queue and acknowledgment rules

1. A new local SOS is saved with its canonical upload entry in the same SQLite transaction. Incoming canonical SOS is saved with its message/operation/upload entry before peer ACK. All nodes retain eligible SOS; only explicitly authorized gateway credentials may upload another origin's operation.
2. The gateway stores the canonical operation JSON separately from prototype status fields. Peer or recipient ACKs cannot clear this upload queue. Reuse of an operation ID with different canonical contents is refused.
3. `NWPathMonitor` only triggers checks. The gateway becomes available after authenticated `/gateway/ready` verifies the backend and database. Network interface presence alone is not success.
4. Push uses exactly rc.2 `PushRequest`. A successful transaction commits the operation, entity, stable `BACKEND_COMMITTED` ACK, change record and incident projection atomically. Multiple gateways can make requests; exactly one durable incident effect is enforced. Distributed radios cannot guarantee zero duplicate network requests.
5. Retrying identical content returns `outcome: "COMMITTED", duplicate: true` and the original ACK. An unchanged operation ID with changed contents is rejected. The gateway only marks its queue committed after validating the HTTP response's operation ID, backend stage, server ID and entity version.
6. Transient failures remain pending with persisted exponential delay (2 seconds to 5 minutes plus jitter). Rejected operations remain blocked and visible; manual retry is available after fixing provisioning or invalid data. A lost response after commit is recovered by identical retry. Restart does not erase pending/blocked entries. Observation metadata is separately retried after commitment.
7. Wire stages stay `PEER_STORED`, `BACKEND_COMMITTED`, `RECIPIENT_ACKNOWLEDGED`. Incident event `SERVER_RECEIVED` describes a backend transaction and is not a fourth wire ACK. Operator incident acknowledgment is not a mesh recipient ACK. Broadcasts do not mean every node acknowledged.
8. `SANDBOX_NOTIFICATION_SUBMITTED` and `SANDBOX_AUTHORITY_ACKNOWLEDGED` never mean an authority was contacted. `AUTHORITY_NOTIFIED` is reserved and cannot be set by a generic operator status command until an authorized real integration exists. Sandbox submission leaves incident status unchanged.
9. Existing reverse-path peer/recipient ACK routing is preserved. This branch does not add a cryptographically authenticated backend-ACK relay to the offline origin. The gateway and dashboard have HTTP-backed commitment evidence; the offline sender may retain only peer receipt evidence until a separately reviewed receipt-sync feature. Do not treat an arbitrary mesh ACK as proof of a trusted backend transaction.

## Additive HTTP API

All JSON timestamps are epoch milliseconds. IDs are lowercase UUIDv4. Bodies reject unknown keys. Required fields are listed unless marked optional. Mutation endpoints require an operator cookie or node-bound bearer as stated. Cookies require an exact matching Origin for mutations; foreign Origin is denied. Browser login is the existing `POST /login` form (`credential`) or `POST /api/v1/operator/session` JSON (`credential`); response sets an HttpOnly SameSite=Strict eight-hour cookie. `POST /api/v1/operator/logout {}` revokes that session.

Core rc.2 push, pull, conflicts, receipts and `/dashboard/snapshot` remain documented in `contracts/v1/README.md`, `field-reference.md`, and `examples.md`. The incident dashboard uses a separate `/emergency/snapshot`; it does not inject extra fields into the frozen draft's snapshot schema.

| Method and path (`/api/v1`) | Permission | Request | Success |
|---|---|---|---|
| GET `/connectivity` | public | none | `text/plain` marker `OFFGRID_INTERNET_OK_V1`, usable as a team-controlled public HTTPS probe; no credentials sent |
| GET `/emergency/incidents` | operator | `cursor=<received_at>_<incidentUUID>&limit=100`, limit 1..500 | `{schemaVersion:1,incidents,nextCursor:string|null}` for older incidents, descending keyset order |
| GET `/gateway/ready` | gateway | none | `{schemaVersion:1,nodeId,serverNodeId,ready:true,timestamp}`; real database query |
| POST `/gateway/heartbeat` | gateway | heartbeat below | `{schemaVersion:1,accepted:true}` |
| POST `/gateway/observations` | gateway that committed/uploaded operation | observation below | `{schemaVersion:1,accepted:true,duplicate:boolean}` |
| GET `/emergency/snapshot` | operator | none | snapshot below |
| GET `/incidents/{incidentId}` | operator, own group | UUID path | `{schemaVersion:1,incident,events,notifications,uploads}` |
| POST `/emergency/commands` | operator, own group | command below | `{schemaVersion:1,commandId,subjectId,revision,duplicate}` |

Heartbeat fields: `schemaVersion:1`, `nodeId:UUID` matching credential, `reportedAt:integer>=0`, `meshConnected:boolean`, `internetReachable:boolean|null` (independent public HTTPS probe; null when not configured), `pendingUploads:integer 0..1000000`, `failedUploads:integer 0..1000000`. Server `observed_at` is authoritative freshness. Current heartbeat means observed within 45 seconds; after that all device-reported connectivity/backlog values are stale, not zero. `backendConnected` is derived from server receipt age. State changes/reconnection are stored; inferred heartbeat expiry is labelled stale, not a fabricated radio disconnection event.

Observation fields: `schemaVersion:1`, `operationId:UUID`, `packetId:UUID`, `hopCount:integer 0..32`, `receivedAt:integer>=0`. Only the first report for a gateway/operation pair is stored; repeat submission is idempotent. It is explicitly labelled self-reported. Full relay paths, forwarding times and location accuracy are unknown unless actually supplied by a future reviewed extension. No coordinates or telemetry are invented.

Example command (synthetic IDs, no credentials):

```json
{"schemaVersion":1,"commandId":"80000000-0000-4000-8000-000000000001","action":"SET_STATUS","subjectId":"80000000-0000-4000-8000-000000000002","expectedRevision":1,"data":{"status":"ACKNOWLEDGED","note":"Operator reviewed SOS"}}
```

| action | subjectId | data fields |
|---|---|---|
| SAVE_AUTHORITY | authority ID, new or existing | `name:string 1..200`, `category:POLICE\|AMBULANCE\|FIRE_RESCUE\|DISASTER\|OTHER`, `contact:string 1..500`, `active:boolean` |
| SAVE_RESPONDER | responder ID, new or existing | `name`, `contact`, `authorityId:UUID`, `active`; authority must be active in same group |
| SET_STATUS | incident ID | `status`, `note:string 1..1000` |
| ASSIGN_AUTHORITY | incident ID | `authorityId:UUID`; active, own group; cannot switch after responder assigned |
| ASSIGN_RESPONDER | incident ID | `responderId:UUID`; active and belongs to assigned authority |
| SANDBOX_NOTIFY | incident ID | `{}`; acknowledged incident and active assigned authority required |
| SANDBOX_ACK | incident ID | `notificationId:UUID` of this incident's pending sandbox notification |

`expectedRevision` is integer >=0; creation uses 0. Each successful command increments the subject revision, retains an audit record, and emits a postcommit notification. Exact command retries by the same operator return the original result with `duplicate:true`; request reuse with changed content returns 409. Always retry the same command ID after ambiguous network failure. The UI retains ambiguous commands in memory for explicit retry; don't reload until resolved. It does not queue offline status changes.

Allowed incident transitions: RECEIVED → ACKNOWLEDGED or CANCELLED; ACKNOWLEDGED/AUTHORITY_NOTIFIED → RESPONDER_ASSIGNED (assignment command), RESOLVED or CANCELLED; RESPONDER_ASSIGNED → RESPONDER_EN_ROUTE, RESOLVED or CANCELLED; RESPONDER_EN_ROUTE → RESOLVED or CANCELLED. RESOLVED and CANCELLED are terminal. `AUTHORITY_NOTIFIED` is reserved for a future authorized provider, unavailable in sandbox.

Snapshot example structure (arrays empty when no records; never seeded automatically):

```json
{"schemaVersion":1,"observedAt":1793740000000,"incidents":[],"authorities":[],"responders":[],"gateways":[],"events":[],"counts":[],"incidentLimit":500,"nextCursor":null}
```

Database projection names are intentionally snake_case; canonical `operation` retains rc.2 camelCase unchanged. `incident` fields: `incident_id`, `group_id`, `operation_id`, `origin_node_id`, `first_gateway_id:UUID|null`, `received_at:decimal string`, `status`, `authority_id:UUID|null`, `responder_id:UUID|null`, `revision:integer`, `operation:Operation`. PostgreSQL bigint fields in projection responses serialize as decimal strings, unlike canonical timestamps which remain numeric. `authority`: `authority_id,group_id,name,category,contact,active,revision`. `responder`: `responder_id,group_id,authority_id,name,contact,active,revision`.

`gateway`: `node_id,display_name,observed_at:string|null,reported_at:string|null,body:Heartbeat|null,successful_uploads:integer,last_successful_upload:string|null,backendConnected:boolean`. Successful uploads count distinct operations acknowledged to that gateway; sums across gateways are not unique incident counts. `counts`: `{status,count:integer}` across all incidents, including older than the displayed limit.

`event`: `event_id,incident_id:UUID|null,actor_id,kind,occurred_at:decimal string,details:object`. Gateway events have a null incident. Incident detail includes all its event rows (also `group_id`) and `notifications`: `{notification_id,incident_id,authority_id,group_id,mode:"SANDBOX",status:SANDBOX_SUBMITTED|SANDBOX_ACKNOWLEDGED,submitted_at:string,acknowledged_at:string|null}`; `uploads`: `{node_id,operation_id,first_seen:string,last_seen:string,attempts:integer,observation:Observation|null}`.

Errors: existing `{schemaVersion:1,error:{code,message,retryable}}`. 401 absent/invalid credential; 403 wrong role/node/group/origin; 404 inaccessible or missing incident; 409 stale revision/ID reuse; 422 invalid payload/transition; 413 oversized request; 429 rate limit (`Retry-After:60`); 503 temporary database/backend failure. Network requests are limited to 600/minute per socket IP in this single-instance MVP; behind a proxy configure an additional trusted-edge limit. Untrusted forwarded-IP headers are ignored. Raw secrets/payloads are not logged. Use encrypted storage/backups and restricted DB access on the deployment host; repository code cannot guarantee host disk encryption.

## Live reads, limitations and acceptance

WebSocket `/ws` emits rc.2 `SYNC_NOTIFICATION` after successful transactions. Notifications are refresh hints; emergency clients fetch the full snapshot. The dashboard reconnects after five seconds and polls every fifteen seconds, including heartbeat expiry. The backend is currently one process; cross-process pub/sub is not implemented. The initial snapshot contains up to 500 incidents and 200 recent events. Load older incidents through the keyset cursor; detail returns full recorded incident history. The map bundles Natural Earth 1:110m public-domain land outlines and WGS84 coordinates locally. It is not street navigation and sends no location data to tile providers.

No tests in this repository prove physical cellular/mesh interoperability. Automation uses native Swift with simulated radio links, real HTTP/PostgreSQL, and browser automation. CI test data is explicitly synthetic and only permitted in `_test` databases. `acceptance-host.mjs` writes random ephemeral credentials outside the repository; CI uploads only screenshots without credential fields.

Physical acceptance requires three real iPhones, a reachable authorized backend, existing IDs/credentials, and Engineer 3's rebuild. Record device/app commit, OS, network conditions, incident/operation IDs, first ACK and duplicate ACK, screenshot and database row count. Keep A and B without internet and no direct A↔C link; C must retain mobile data. Confirm A→B→C forwarding, C's persisted queue, backend commit, one incident, UI acknowledgment, sandbox notification and history. Then disconnect C during upload, restart it with queued SOS, reconnect and verify identical retry; repeat simultaneous duplicate uploads from two gateways, invalid payload, missing coordinates, multiple SOS, gateway stale/recovery, and baseline offline chat/SOS. Never write “physical pass” based on simulations. Device testing remains pending until the team supplies measured results.
