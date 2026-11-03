import pg from "pg";
import { createHash, randomBytes } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { ApiError } from "./contract.js";
export type Actor = {
  node_id: string;
  group_id: string;
  role: "node" | "gateway" | "operator" | "server";
  kind: "bearer" | "session";
};
export const hash = (token: string) =>
  createHash("sha256").update(token).digest("hex");
export const token = () => randomBytes(32).toString("base64url");
export function pool(url = process.env.DATABASE_URL) {
  if (!url) throw new Error("DATABASE_URL is required");
  const p = new pg.Pool({
    connectionString: url,
    max: 10,
    connectionTimeoutMillis: 5000,
  });
  p.on("error", () => console.error("Idle database connection failed"));
  return p;
}
export async function migrate(p: pg.Pool) {
  const c = await p.connect();
  try {
    await c.query("BEGIN");
    await c.query("SELECT pg_advisory_xact_lock(64820312)");
    await c.query(
      "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    const dir = new URL("../../../database/migrations/", import.meta.url);
    for (const name of readdirSync(dir)
      .filter((n) => /^\d+.*\.sql$/.test(n))
      .sort()) {
      if (
        (await c.query("SELECT 1 FROM schema_migrations WHERE name=$1", [name]))
          .rowCount
      )
        continue;
      await c.query(readFileSync(new URL(name, dir), "utf8"));
      await c.query("INSERT INTO schema_migrations(name) VALUES($1)", [name]);
    }
    await c.query("COMMIT");
  } catch (e) {
    await c.query("ROLLBACK");
    throw e;
  } finally {
    c.release();
  }
}
export async function provision(
  p: pg.Pool,
  id: string,
  name: string,
  role: Actor["role"] = "node",
  platform = "iOS",
  group = "local-demo",
) {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      id,
    ) ||
    !["node", "gateway", "operator"].includes(role)
  )
    throw new Error("Valid UUIDv4 and provisioning role required");
  if (!["iOS", "Android", "Windows", "macOS", "Linux", "Web", "Server"].includes(platform)) throw new Error("Unsupported platform");
  const secret = token(),
    c = await p.connect();
  try {
    await c.query("BEGIN");
    const existing = await c.query(
      "SELECT group_id,role FROM nodes WHERE node_id=$1 FOR UPDATE",
      [id],
    );
    if (
      existing.rowCount &&
      (existing.rows[0].group_id !== group || existing.rows[0].role !== role)
    )
      throw new Error(
        "Existing identity role/group cannot be silently changed",
      );
    await c.query(
      "INSERT INTO nodes(node_id,group_id,display_name,platform,role) VALUES($1,$2,$3,$4,$5) ON CONFLICT(node_id) DO UPDATE SET display_name=excluded.display_name, platform=excluded.platform",
      [id, group, name, platform, role],
    );
    await c.query(
      "INSERT INTO credentials(token_hash,node_id,kind) VALUES($1,$2,'bearer')",
      [hash(secret), id],
    );
    await c.query("COMMIT");
    return secret;
  } catch (e) {
    await c.query("ROLLBACK");
    throw e;
  } finally {
    c.release();
  }
}
export async function authenticate(
  p: pg.Pool,
  secret: string,
  kind: "bearer" | "session",
): Promise<Actor> {
  if (!secret) throw new ApiError(401, "UNAUTHORIZED", "Credential required");
  const r = await p.query(
    "SELECT n.*,c.kind FROM credentials c JOIN nodes n USING(node_id) WHERE token_hash=$1 AND c.kind=$2 AND NOT revoked AND (expires_at IS NULL OR expires_at>now())",
    [hash(secret), kind],
  );
  if (!r.rowCount)
    throw new ApiError(401, "UNAUTHORIZED", "Invalid or expired credential");
  const actor = r.rows[0] as Actor;
  await p.query("UPDATE nodes SET last_seen=$2 WHERE node_id=$1", [
    actor.node_id,
    Date.now(),
  ]);
  return actor;
}
