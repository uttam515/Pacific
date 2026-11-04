# OFFGRID operations dashboard

React + TypeScript + Vite dashboard for Engineer 1. Includes Overview, Network, Synchronization, Gateways, Conflicts, and Emergencies. All sample data is explicitly labeled **Demo**. The app never substitutes demo data when a live server fails.

## Run on Windows, macOS, or Linux

Install Node.js 20.19+ (Node.js 22 LTS or newer is recommended), then from the repository root:

```sh
cd apps/web-dashboard
npm ci
npm run dev
```

Open the local URL printed by Vite. Production verification:

```sh
npm test
npm run build
npm run preview
```

The production build precaches its application shell through a service worker. Visit once while connected before testing an offline reload. Service workers require HTTPS or localhost. Vite development mode deliberately does not register the worker. No CDN, external fonts, map tiles, analytics, or AI/API keys are required.

## Features

- Responsive layout and accessible native modal dialogs with focus restoration.
- Clickable topology, searchable node inventory, node detail dialog, observed timestamps.
- Searchable/filterable operation queue. Distinct queued, relayed, synchronized, and conflict states.
- SOS acknowledgment/resolution, version comparison, announcement composer, JSON snapshot export.
- Demo controls: gateway failure/recovery, incoming SOS, pending sync, explicit reset.
- IndexedDB persists demo changes, cached live snapshots, and queued live actions separately by backend URL.
- Live REST polling every 15 seconds; optional WebSocket notifications request immediate refresh.
- Durable action outbox; failed uploads stay queued. Only a matching server acknowledgment removes an action.
- Offline/disconnected/stale indicators; no invented nodes or telemetry in live mode.

## Backend integration

Read `../../docs/dashboard-integration.md`. The existing API draft does **not** yet implement the endpoints this dashboard needs. The live adapter is ready to connect to that contract, but this change does not implement the backend, mobile networking, actual gateway election, or conflict arbitration.

Connection settings accepts the API base URL (for example `http://localhost:4000/api/v1` locally) and optional WebSocket URL. HTTPS-hosted dashboards require HTTPS/WSS backends. Sessions use cookies; configure backend authentication and explicit credentialed CORS for the dashboard origin. Credentials are not stored in the app.

## Source layout

- `src/domain.ts`: snapshot types, validator, isolated demo behavior.
- `src/storage.ts`: IndexedDB transactions and scoped outboxes.
- `src/api.ts`: bounded HTTP requests, response validation, acknowledgment checks.
- `src/App.tsx`: operations screens, live lifecycle, operator interactions.
- `src/styles.css`: responsive visual system and reduced-motion support.
- `scripts/offline-build.mjs`: versioned production application cache.
- `tests/domain.test.ts`: failure, deduplication-state, conflict, and queue behavior tests.

## Verification limits

A running dashboard does not prove physical mesh connectivity. Live hardware, packet forwarding, backend persistence and idempotence, authentication, and cross-platform transport must be verified with Engineers 2 and 3. The demo's node positions are illustrative; live layout displays reported edges with automatic positions, not physical coordinates.
