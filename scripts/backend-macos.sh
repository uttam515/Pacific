#!/bin/bash
# Local deployment helper. Run ON the Mac that will host the backend.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Run this helper on the hosting Mac. See docs/backend-local-setup.md for Windows.' >&2; exit 1; fi
command -v node >/dev/null || { echo 'Install Node.js 22 LTS or newer first.' >&2; exit 1; }
node -e 'if(Number(process.versions.node.split(".")[0])<22)process.exit(1)' || { echo 'Node.js 22+ is required.' >&2; exit 1; }
command -v docker >/dev/null || { echo 'Install and start Docker Desktop first.' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Start Docker Desktop, then retry.' >&2; exit 1; }
state='.env.backend.local'
if [[ ! -e "$state" ]]; then
  # Credentials remain local data; never evaluate this file as shell code.
  (umask 077; node -e 'const fs=require("fs"),c=require("crypto");const p=c.randomBytes(32).toString("base64url");fs.writeFileSync(".env.backend.local",`POSTGRES_PASSWORD=${p}\nDATABASE_URL=postgresql://offgrid:${p}@127.0.0.1:5432/offgrid\n`,{flag:"wx",mode:0o600})')
fi
if [[ -L "$state" ]]; then echo 'Refusing a symbolic link for credential storage.' >&2; exit 1; fi
chmod 600 "$state"
# Shell environment overrides compose env files: refuse ambiguous password input.
if [[ -n "${POSTGRES_PASSWORD:-}" || -n "${DATABASE_URL:-}" ]]; then echo 'Unset POSTGRES_PASSWORD and DATABASE_URL first; this helper reuses .env.backend.local.' >&2; exit 1; fi
if [[ "${1:-}" == 'setup' ]]; then
  npx --yes pnpm@12.9.1 install --frozen-lockfile
  npx --yes pnpm@12.9.1 run contract:types:check
  npx --yes pnpm@12.9.1 run build
  docker compose --env-file "$state" -f compose.backend.yml up -d --wait
  node --env-file="$state" services/api-server/dist/cli.js migrate
  node --env-file="$state" services/api-server/dist/cli.js status
  echo 'Setup complete. Next: provision your EXISTING iOS ID using the macOS guide, then run bash scripts/backend-macos.sh start.'
elif [[ "${1:-}" == 'start' ]]; then
  [[ -f services/api-server/dist/index.js ]] || { echo 'Run setup first.' >&2; exit 1; }
  interface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2;exit}')
  host="${LAN_HOST:-}"
  if [[ -z "$host" && -n "$interface" ]]; then host=$(ipconfig getifaddr "$interface" 2>/dev/null || true); fi
  [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { echo 'No usable LAN address found. Set LAN_HOST to the actual Mac LAN IP/hostname and retry.' >&2; exit 1; }
  export HOST='0.0.0.0' PORT='4000' ALLOW_INSECURE_LOCAL='1' DASHBOARD_ORIGIN="http://$host:4000"
  echo "Candidate LAN API: $DASHBOARD_ORIGIN/api/v1"
  echo "Operator login: $DASHBOARD_ORIGIN/login"
  echo 'Trusted local HTTP test only. Reachability is NOT verified until the iPhone health check succeeds. Keep this terminal open.'
  exec node --env-file="$state" services/api-server/dist/index.js
else echo 'Usage: bash scripts/backend-macos.sh setup|start' >&2; exit 1; fi
