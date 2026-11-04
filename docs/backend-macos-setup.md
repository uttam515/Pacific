# Run the pinned OFFGRID backend on the hosting Mac

**Host-side runbook, not a claim that a team Mac is already deployed.** Contract stays pinned to `d321ccbf0166a78aa6c07d8803167ebe640d8e3d`. PR #4 remains draft. No iOS installation ID is generated or changed by this guide.

Prerequisites: Node.js 22 LTS or newer, Git, Docker Desktop installed and running Linux containers; Mac and iPhone on a trusted LAN that allows client-to-client traffic. Guest Wi-Fi/client isolation may prevent this. Running the backend on the iOS engineer's Mac avoids transferring the credential between laptops.

## 1. Obtain the backend branch

For a new checkout (choose a different destination if this folder exists):

```bash
git clone --branch feature/backend-foundation https://github.com/uttam515/Pacific.git Pacific-backend
cd Pacific-backend
```

For an existing clean checkout, fetch and switch to `feature/backend-foundation`. Stop if Git reports local changes; do not discard or force-reset team work. The current backend branch is stacked on the contract branch; checking out `develop` alone does not yet include this draft backend.

## 2. Prepare PostgreSQL, build, migrate, verify

From repository root in macOS Terminal:

```bash
bash scripts/backend-macos.sh setup
```

The helper installs locked dependencies, verifies generated types, builds, starts PostgreSQL 16, runs migrations, and verifies all required tables. It creates `.env.backend.local` only if absent, with a random database password and DATABASE_URL; that file is ignored by Git and chmod 600. It reuses the file on every run. Do not paste its contents, commit it, source it as a shell script, or regenerate its password while reusing the database volume. If shell POSTGRES_PASSWORD or DATABASE_URL is already set, the helper stops to avoid overriding its saved database credentials.

If this Mac already has a PostgreSQL Docker volume for this project, use the original database password/configuration. A freshly generated password does not rotate an existing database's password. Do not delete the volume to resolve an authentication error if it contains wanted data.

Successful status output lists `001_backend.sql`, reports `database: reachable`, and `requiredTables: verified`. Re-running migrations is safe and does not clear data. To inspect the recorded migration independently:

```bash
docker compose --env-file .env.backend.local -f compose.backend.yml exec postgres psql -U offgrid -d offgrid -c 'SELECT name, applied_at FROM schema_migrations ORDER BY name;'
```

The setup helper is macOS-specific and has shell syntax validation; actual execution on a team Mac remains a host-side step. PostgreSQL application behavior has been verified separately by the real PostgreSQL CI job.

## 3. Provision the EXISTING iOS identity privately

Obtain the current installation node UUID from the iOS engineer's contract-compatible build. It must be the ID associated with that app's existing outbox, after its controlled identity migration. Do not create a replacement UUID or edit old operation origins.

Create a private directory OUTSIDE the repository:

```bash
install -d -m 700 "$HOME/.offgrid"
IOS_NODE_ID='<replace-with-existing-iOS-installation-UUID>'
node --env-file=.env.backend.local services/api-server/dist/cli.js provision "$IOS_NODE_ID" 'iPhone A' node iOS --credential-file "$HOME/.offgrid/iphone-a.json"
```

Replace the placeholder before running. This writes the node-bound credential to a NEW file with mode 600. Standard output contains the node ID/path, never the credential. It refuses to overwrite a file; if writing fails, it revokes the newly created credential. Enter the credential directly into the iPhone's secure configuration from that private file (for example, inspect it locally in a private editor). Do not paste it into GitHub, this chat, logs, screenshots, or a shared document. If another person needs it, use an agreed encrypted secret-sharing channel, not ordinary chat. The UUID is not a bearer credential.

If provisioning a direct message, register the actual intended recipient ID as well. An SOS CREATE does not require a recipient ID. All nodes default to the trusted `local-demo` group. Do not accidentally grant gateway/operator roles to the iPhone.

## 4. Provision operator login separately

An operator identity is separate from the iOS installation. Generating this UUID does not replace the phone's ID:

```bash
OPERATOR_NODE_ID=$(node -e 'console.log(require("crypto").randomUUID())')
node --env-file=.env.backend.local services/api-server/dist/cli.js provision "$OPERATOR_NODE_ID" 'Operator' operator Web --credential-file "$HOME/.offgrid/operator.json"
```

Keep this credential local too. The default terminal-print provisioning mode still exists for compatibility; deployment should use `--credential-file`.

## 5. Start the API on port 4000

```bash
bash scripts/backend-macos.sh start
```

It binds to `0.0.0.0:4000`, detects the default interface address, and prints a **candidate** LAN API URL and operator login URL. Keep Terminal and Docker running, and keep the Mac awake during the session. The address is not declared reachable until tested from the iPhone.

If automatic detection picks a VPN/other interface, supply the actual LAN address:

```bash
LAN_HOST='<actual-Mac-LAN-IP-or-hostname>' bash scripts/backend-macos.sh start
```

Do not type the angle-bracket placeholder literally. Use macOS System Settings → Network to identify the connected interface/address. Wi-Fi may not be `en0`. Do not disable the firewall globally: allow only the intended Node backend/private-LAN access if a prompt or policy requires it. If port 4000 is already occupied, identify its owner; do not kill unrelated team services.

This helper deliberately opts into trusted local HTTP and non-Secure development cookies. Credentials are not encrypted over HTTP. Use only an agreed trusted test LAN; use an HTTPS reverse proxy/trusted certificate for shared or public deployment. iOS owns its development ATS/local-network permissions. No tunnel/public deployment is created here.

## 6. Verify operator login and actual live snapshots

Use the EXACT printed LAN host consistently; do not switch between `localhost`, LAN IP, and another hostname.

1. On the Mac, open `http://<Mac-LAN-IP>:4000/api/v1/health`. Expected: `{"schemaVersion":1,"status":"ok"}`. This confirms the HTTP process; use database status and snapshots for database verification.
2. Open `http://<Mac-LAN-IP>:4000/login`. Enter the operator credential from the private file. It sets an HttpOnly session cookie and redirects to the built dashboard.
3. In dashboard **Connection settings**, set API base `http://<Mac-LAN-IP>:4000/api/v1` and optional WebSocket `ws://<Mac-LAN-IP>:4000/ws`. Select **Connect backend**. It must display live backend status instead of Demo data.
4. Open `http://<Mac-LAN-IP>:4000/api/v1/dashboard/snapshot` in another tab in the same browser. Expected: schemaVersion 1, real provisioned nodes, initially empty operation/alert collections. Without a valid operator session, expect 401/403. No sample operations are inserted by setup.
5. Return to the dashboard and verify the same real node IDs/names. No topology links should be invented. The dashboard action buttons are still gated; this stage verifies login and live snapshot reading.
6. Disconnect the browser/network temporarily; verify cached data becomes disconnected/stale. Reconnect and verify a real refresh. Losing a WebSocket notification must not prevent the 15-second REST refresh.

## 7. Verify phone reachability BEFORE sending credentials

On the physical iPhone, using the same LAN, open `http://<Mac-LAN-IP>:4000/api/v1/health` in Safari. A successful JSON response proves that address/port is reachable at that time. It does not prove the native app's ATS settings, authentication, database sync, or persistence.

If it fails, check the address, Mac awake state, Docker/backend terminals, host firewall, VPN routing, and Wi-Fi client isolation. Do not call the URL reachable or share a fabricated address from another machine. Once it succeeds, give the iOS engineer this non-secret API base: `http://<actual-Mac-LAN-IP>:4000/api/v1`. The address can change when joining another network.

The iOS app then uses its privately provisioned credential in `Authorization: Bearer ...`, and the existing node ID as request.nodeId. Start with one operation, see COMMITTED and its backend ACK, verify the ID in the live dashboard, then retry the identical operation and verify duplicate=true and the unchanged ACK/entityVersion.

## Host-side handoff checklist

Record the backend code commit, pinned contract SHA, migration names, port, non-secret LAN base URL, health result from Mac and iPhone, operator login result, live snapshot result, and first operation/duplicate results. Record credentials only as `provisioned privately: yes/no`. Never attach the credential files. Keep PR #4 draft until physical integration testing is complete.
