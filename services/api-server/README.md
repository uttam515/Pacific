# OFFGRID backend foundation

Pinned Contract rc.2: `d321ccbf0166a78aa6c07d8803167ebe640d8e3d`.

See [local backend setup](../../docs/backend-local-setup.md) for PostgreSQL, migrations, private node provisioning, same-origin operator login, LAN/HTTPS setup, supported endpoints, test commands, and current limitations.

- `migrate`: apply versioned SQL migrations; DATABASE_URL required.
- `provision`: create a node-bound credential, printed privately once.
- `start`: run compiled HTTP/WebSocket server (build first).
- `test`: unit tests; no database substitutes.
- `test:integration`: real PostgreSQL plus HTTP/WebSocket, disposable TEST_DATABASE_URL ending `_test` required.

The dashboard action adapter is gated; live snapshot reading and canonical receipt/conflict APIs are separate. This is implemented source under review, not a claim of a deployed URL or physical iPhone acceptance.
