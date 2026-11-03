# Dashboard integration contract — proposed v1 extension

Owner: Engineer 1. This extends `api-contract.md` without changing existing mobile endpoints or packet types. The dashboard currently ships with an explicitly labeled browser-local demo. These endpoints must be implemented by the backend before live mode can populate.

## Snapshot

`GET /api/v1/dashboard/snapshot`

Return JSON matching `Snapshot` in `apps/web-dashboard/src/domain.ts`:

```json
{
  "schemaVersion": 1,
  "observedAt": 1793721600000,
  "nodes": [],
  "links": [],
  "operations": [],
  "alerts": [],
  "conflicts": [],
  "gateways": [],
  "events": []
}
```

All timestamps are epoch milliseconds. Supply real measurement timestamps, not fresh timestamps for stale data. `nodes[].lastSeen` records the last confirmed observation. Links reference node IDs and represent measured/reported links, not inferred radio reach. Gateway `selected` comes from the network engine; the dashboard does not elect a gateway. `operations[].conflictId` may reference a conflict. Keep the returned snapshot bounded (recommend 100 recent operations/events and the current active inventory); the operation UI caps rendered rows at 100. A future server pagination contract is needed for large deployments.

Node: id, name, platform, role (`client|relay|gateway`), status (`active|unreachable`), lastSeen, optional battery.

Operation: id, origin (node ID), kind, status (`queued|relayed|synced|conflict`), createdAt, hops, optional conflictId.

Alert: id, title, category, location (display text), nodeId, status (`new|acknowledged|resolved`), createdAt.

Conflict: id, entity (display title), baseVersion, left, right (text versions), leftNode, rightNode (display names), optional resolved (`left|right`). Preserve both alternatives after resolution.

Gateway: nodeId, reachable (backend probe result), selected, latency (milliseconds).

Event: id, title, detail, time, kind (`info|success|warning`).

## Actions

`POST /api/v1/dashboard/actions`

```json
{
  "operationId": "uuid",
  "type": "ACK_ALERT",
  "entityId": "sos-001",
  "createdAt": 1793721600000
}
```

Also send `Idempotency-Key: <operationId>`. Supported types:

| Type | Required fields | Backend responsibility |
| --- | --- | --- |
| ACK_ALERT | entityId | Record authenticated operator acknowledgment |
| RESOLVE_ALERT | entityId | Record resolution, preserving audit history |
| RESOLVE_CONFLICT | entityId, choice (`left|right`) | Revalidate current conflict/version and preserve alternatives |
| RETRY_SYNC | none | Request network-engine retry; acceptance does not imply synchronization |
| CREATE_ANNOUNCEMENT | text (3–1000 characters) | Save/broadcast announcement as an operation |

Return success only after durable commit:

```json
{"acceptedOperationId":"same-uuid"}
```

The same operation ID must never apply twice. An already accepted retry returns the same acknowledgment. The dashboard retains actions on timeout, non-2xx response, or mismatched acknowledgment; retries run every 15 seconds and on browser connectivity changes. Rejected actions remain queued, so the backend must not return acceptance for invalid operations. Future work: a typed permanent-rejection response and operator queue management.

The UI never marks live alerts resolved optimistically: server snapshots are authoritative. Queue storage is scoped by backend URL. Network retries can occur after restart. Backend conflict checks must reject stale resolutions instead of silently overriding a newer edit.

## Live events

Optional WebSocket endpoint as configured in settings (e.g. `wss://host/ws`). Any incoming message triggers a coalesced snapshot refresh. Polling remains the fallback, and socket reconnect attempts occur every 5 seconds. No packet transport is implemented in the dashboard WebSocket.

## Security and offline deployment

Use authenticated sessions, authorize operator actions, validate every payload, and use explicit credentialed CORS for the dashboard's origin. Cross-origin cookie policies may require a same-origin proxy in production. Do not embed secrets in frontend bundles. Serve via HTTPS; localhost is appropriate for development. Backend data is never service-worker cached; the validated snapshot and action queue are stored in IndexedDB. Browser storage may be cleared by the user, so it is not a substitute for backend backups.

## Team acceptance test

1. Real phone generates an operation offline and persists it after restart.
2. Participating relay/gateway uploads it using the agreed mobile protocol.
3. Backend commits once, acknowledges, and updates the dashboard snapshot.
4. Dashboard displays the true origin and state.
5. Interrupt connectivity; dashboard labels cached data and retains operator actions locally.
6. Restore connectivity; duplicate uploads do not create duplicate effects.
7. Concurrent announcement edits preserve both versions and require an authorized resolution.

These steps require backend and physical-device integration; the local demo is not evidence that they passed.
