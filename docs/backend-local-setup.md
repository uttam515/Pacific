# Backend foundation — pinned Contract v1 rc.2

Contract commit: **d321ccbf0166a78aa6c07d8803167ebe640d8e3d**. This backend PR is stacked on that immutable commit. It does not freeze or merge PR #3. `services/api-server/contract-pin.json` records the schema digest; startup rejects unexpected schema changes. Generated TypeScript models are checked with `pnpm contract:types:check`.

## Implemented versus pending

Implemented code: versioned PostgreSQL migrations; hashed node credentials and revocation checks; authenticated push; per-operation transactions; global mutation serialization plus unique IDs; canonical request comparison; durable ACKs; cursor pull; conflict preservation/guarded resolution; authorized application receipts; database-backed operator snapshot; WebSocket post-commit notification hints; same-origin operator login; static dashboard serving.

Pending: physical iPhone integration, a shared reachable LAN/HTTPS deployment, native model migration, Android/BLE/routing, production security hardening and capacity tests. `/dashboard/actions` is deliberately rejected until the UI command adapter includes canonical operations and resolution guards. Use the versioned APIs for receipt/conflict tests. Snapshots currently project two-candidate conflicts; full candidates remain available from the canonical conflict API. Reading live data through the dashboard is supported; its demo controls are not backend controls.

The small MVP serializes mutations through one commit_clock row to ensure change-log cursor order follows commit order. This favors correctness over throughput; it is not a scalable mesh backend claim. There is one server process's WebSocket fan-out. Multiple server instances require shared notification fan-out; REST polling still catches database changes.

For macOS, use the dedicated [hosting Mac runbook](backend-macos-setup.md) and `scripts/backend-macos.sh`. It preserves a local database credential file and supports non-printing private node provisioning.

## Windows PowerShell setup

Prerequisites: Git, Node.js 22 LTS or newer, Docker Desktop running Linux containers. Use the backend feature branch from its PR. Run from repository root; no real credentials belong in source or chat.

```powershell
npx --yes pnpm@12.9.1 install --frozen-lockfile
$env:POSTGRES_PASSWORD = node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64url'))"
docker compose -f compose.backend.yml up -d --wait
$env:DATABASE_URL = "postgresql://offgrid:$($env:POSTGRES_PASSWORD)@127.0.0.1:5432/offgrid"
npx --yes pnpm@12.9.1 --filter @offgrid/api-server migrate
npx --yes pnpm@12.9.1 run build
```

Keep the password available securely on your laptop: a NEW environment password will not change an existing database volume's password. Subsequent sessions must use the original value. `docker compose down` preserves the named volume. Do not delete the volume to fix an authentication mistake if it contains wanted data. Migrations are transactional and recorded; they do not reset existing data.

Provision the actual installation ID supplied by the iOS engineer. Do not generate a replacement ID for an existing outbox. Placeholder text below must be replaced with the actual lowercase UUIDv4.

```powershell
$iosNodeId = '<actual-iPhone-installation-UUID>'
npx --yes pnpm@12.9.1 --filter @offgrid/api-server provision $iosNodeId 'iPhone A' node iOS
```

The command prints a bearer credential ONCE to your terminal; copy it privately to that iPhone's secure configuration. Only its SHA-256 hash is stored in PostgreSQL. Re-running creates an additional credential, not an automatic rotation. Revoke old credentials with an administrator SQL operation (`UPDATE credentials SET revoked=true WHERE token_hash=...`) when rotating. Role/group cannot silently change through provisioning.

Provision the message recipient's node ID as well, or start with an SOS CREATE (no recipient ID). Create an operator identity separately:

```powershell
$operatorNodeId = node -e "console.log(require('crypto').randomUUID())"
npx --yes pnpm@12.9.1 --filter @offgrid/api-server provision $operatorNodeId 'Operator' operator Web
```

Both mobile and operator identities default to the trusted `local-demo` group. Gateway role is an explicit grant to upload same-group origins, not an untrusted peer authenticity guarantee. Credentials remain bound to their uploading node. For the first direct iPhone test use role `node`.

## Start a trusted local test server

```powershell
$env:HOST = '0.0.0.0'
$env:PORT = '4000'
$env:ALLOW_INSECURE_LOCAL = '1'
$env:DASHBOARD_ORIGIN = 'http://<your-computer-LAN-IP>:4000'
npx --yes pnpm@12.9.1 --filter @offgrid/api-server start
```

Replace the LAN IP first. The iPhone and browser must use that same origin. This explicitly enables plaintext HTTP/non-Secure cookies for a trusted development network only. Use HTTPS at a reverse proxy and remove ALLOW_INSECURE_LOCAL for shared/public deployment. No public tunnel or public endpoint is created by these commands. A user's laptop `localhost` address is not reachable from an iPhone. Permit port 4000 only on the intended private LAN through the laptop firewall. iOS owns its local-network and development ATS configuration; do not assume the contract grants those permissions.

Open `http://<LAN-IP>:4000/login` in your browser and paste the operator credential into the local password form. This creates an HttpOnly SameSite session cookie; no token is added to a URL. The dashboard is served at `/`. In Connection settings select API base `http://<LAN-IP>:4000/api/v1` and optional socket `ws://<LAN-IP>:4000/ws`, then connect. Use the same host (not a mixture of localhost and LAN IP) to keep cookies and Origin checks consistent. Refresh returns cached data/stale labels if disconnected; polling remains the fallback.

## Mobile requests

Base URL: `http://<LAN-IP>:4000/api/v1` for the explicit local test, HTTPS for deployed testing. Supply:

```text
Authorization: Bearer <the privately provisioned node credential>
Content-Type: application/json
```

POST `/sync/push` with rc.2 `PushRequest` (schemaVersion 1, authenticated nodeId, operations[]). Use the pinned `packages/protocol/fixtures/v1` shapes, replacing synthetic IDs with actual installation/recipient/entity/operation UUIDs. Payload is an object, not escaped JSON. The response is the exact `PushResponse`: each result is COMMITTED (with duplicate boolean), CONFLICT, or REJECTED. Only COMMITTED is backend commitment. Do not rename duplicates to a DUPLICATE outcome.

GET `/sync/pull?cursor=c0&limit=100`, then persist nextCursor with received changes. POST `/receipts` accepts authorized PEER_STORED/RECIPIENT_ACKNOWLEDGED, never a forged backend commitment. GET `/conflicts`, GET `/conflicts/{id}`, POST `/conflicts/{id}/resolve` follow rc.2. The operator's token may exercise conflict APIs from a local API client, or use a same-origin operator cookie plus Origin header.

POST `/operator/session` is a local operator-session bootstrap extension, separate from the mobile wire contract: operator bearer header, JSON `{}`, Origin matching DASHBOARD_ORIGIN. Browser users should use `/login`. No anonymous registration, open CORS, or URL token auth is enabled.

## Error behavior

- Missing/invalid/expired credential: HTTP401 UNAUTHORIZED; wrong node/role/origin: HTTP403 FORBIDDEN.
- Malformed JSON: HTTP400; invalid typed body: HTTP422 VALIDATION_ERROR; oversized body: HTTP413 TOO_LARGE.
- Push semantic errors are per-operation REJECTED results; successful earlier batch operations remain committed.
- Changed content with an existing operation ID: ID_REUSE, never a new effect.
- Unknown receipt operation: HTTP404 ENTITY_NOT_FOUND, retryable=true; upload the operation first.
- Stale conflict guards: HTTP409 STALE_RESOLUTION; reload before a new resolution.
- Transient backend failure: HTTP503 TEMPORARY_FAILURE, retryable=true. A timeout means unknown outcome: retry the same operation IDs.

## Verification

Unit and shared fixture tests do not establish database correctness. The dedicated GitHub Actions job uses real PostgreSQL 16 plus actual HTTP/WebSocket clients. It tests concurrent uploads, stable duplicate ACKs, lost HTTP response after commit, changed-ID reuse, cursor recovery, real database snapshots, conflict guards, recipient authorization, operator cookies, and new-connection persistence. It does not run an iPhone or reboot PostgreSQL.

To run integration tests locally, create a separate disposable database ending `_test`. The test suite TRUNCATES its application tables and must never target your integration/demo database:

```powershell
docker compose -f compose.backend.yml exec postgres createdb -U offgrid offgrid_test
$env:TEST_DATABASE_URL = "postgresql://offgrid:$($env:POSTGRES_PASSWORD)@127.0.0.1:5432/offgrid_test"
npx --yes pnpm@12.9.1 --filter @offgrid/api-server test:integration
```

First joint acceptance: actual iPhone saves an operation → push commits in PostgreSQL → same ID appears in authenticated live dashboard → identical retry returns COMMITTED, duplicate=true, same ACK and entityVersion, one durable entity effect. Then interrupt a response and retry after recovery. Record actual build SHA and IDs, without credentials. Physical success remains unverified until that test is run.
