import { isSnapshot, type Action, type Snapshot } from "./domain.ts";
export type Connection = { apiUrl: string; wsUrl: string };
export function validateConnection(c: Connection) {
  const api = new URL(c.apiUrl);
  if (
    !["http:", "https:"].includes(api.protocol) ||
    api.username ||
    api.password ||
    api.search ||
    api.hash
  )
    throw new Error(
      "Use an HTTP(S) base URL without credentials, query parameters, or fragments.",
    );
  if (location.protocol === "https:" && api.protocol === "http:")
    throw new Error(
      "This secure dashboard requires an HTTPS backend. For local HTTP development, run the dashboard locally.",
    );
  if (c.wsUrl) {
    const ws = new URL(c.wsUrl);
    if (!["ws:", "wss:"].includes(ws.protocol) || ws.username || ws.password)
      throw new Error("Enter a valid WebSocket URL.");
    if (location.protocol === "https:" && ws.protocol === "ws:")
      throw new Error("Use WSS with this secure dashboard.");
  }
}
async function request(c: Connection, path: string, init?: RequestInit) {
  const r = await fetch(`${c.apiUrl.replace(/\/$/, "")}${path}`, {
    ...init,
    signal: AbortSignal.timeout(8000),
    headers: { "Content-Type": "application/json", ...init?.headers },
    credentials: "include",
  });
  if (!r.ok) throw new Error(`Backend returned HTTP ${r.status}`);
  return r.json();
}
export async function fetchSnapshot(c: Connection): Promise<Snapshot> {
  const data = await request(c, "/dashboard/snapshot");
  if (!isSnapshot(data))
    throw new Error("Backend snapshot does not match the dashboard contract.");
  return data;
}
export async function sendAction(c: Connection, a: Action) {
  const data = await request(c, "/dashboard/actions", {
    method: "POST",
    body: JSON.stringify(a),
    headers: { "Idempotency-Key": a.operationId },
  });
  if (data.acceptedOperationId !== a.operationId)
    throw new Error(
      "Action remains queued: matching server acknowledgment missing.",
    );
}
