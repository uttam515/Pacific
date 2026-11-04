import { randomUUID } from "node:crypto";
import { pool, migrate, provision, hash } from "./database.js";
import type { Actor } from "./database.js";
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
const db = pool();
try {
  const args = process.argv.slice(2);
  const flag = args.indexOf("--credential-file");
  let credentialFile: string | undefined;
  if (flag !== -1) {
    if (!args[flag + 1] || args[flag + 1].startsWith("--"))
      throw new Error("--credential-file requires a path");
    credentialFile = resolve(args[flag + 1]);
    args.splice(flag, 2);
  }
  const [
    command,
    id,
    name,
    role = "node",
    platform = "iOS",
    group = "local-demo",
  ] = args;
  if (command === "migrate") {
    await migrate(db);
    console.log("Database migrations applied");
  } else if (command === "status") {
    const migrations = (
      await db.query(
        "SELECT name,applied_at FROM schema_migrations ORDER BY name",
      )
    ).rows;
    const tables = [
      "nodes",
      "credentials",
      "commit_clock",
      "operations",
      "entities",
      "acknowledgments",
      "conflicts",
      "changes",
      "gateway_events", "incidents", "incident_events", "authorities", "responders", "gateway_health", "gateway_uploads", "emergency_commands", "emergency_audit", "authority_notifications",
    ];
    for (const table of tables)
      await db.query(`SELECT 1 FROM ${table} LIMIT 0`);
    console.log(
      JSON.stringify(
        { database: "reachable", migrations, requiredTables: "verified" },
        null,
        2,
      ),
    );
  } else if (command === "grant-gateway" && id) {
    const c=await db.connect();
    try {
      await c.query("BEGIN");
      const r=await c.query("UPDATE nodes SET role='gateway' WHERE node_id=$1 AND role='node' RETURNING group_id",[id]);
      if(!r.rowCount) throw new Error("An existing node role is required; identity is not replaced");
      await c.query("INSERT INTO emergency_audit VALUES($1,$2,$3,'HOST_GRANT_GATEWAY',$3,$4,$5)",[randomUUID(),r.rows[0].group_id,id,Date.now(),{source:"authorized host provisioning CLI"}]);
      await c.query("COMMIT"); console.log(JSON.stringify({nodeId:id,role:"gateway",identityPreserved:true}));
    } catch(e) {await c.query("ROLLBACK");throw e;}finally{c.release();}
  } else if (command === "provision" && id && name) {
    const secret = await provision(
      db,
      id,
      name,
      role as Actor["role"],
      platform,
      group,
    );
    const value = {
      nodeId: id,
      bearerCredential: secret,
      note: "Private credential; transfer directly to device secure storage. Never commit or paste into chat.",
    };
    if (credentialFile) {
      try {
        // Exclusive creation prevents overwriting an existing device credential.
        writeFileSync(credentialFile, JSON.stringify(value, null, 2) + "\n", {
          mode: 0o600,
          flag: "wx",
        });
      } catch (e) {
        await db.query(
          "UPDATE credentials SET revoked=true WHERE token_hash=$1",
          [hash(secret)],
        );
        throw e;
      }
      console.log(
        JSON.stringify(
          { nodeId: id, credentialFile, credentialPrinted: false },
          null,
          2,
        ),
      );
    } else {
      // Backward-compatible terminal output; use --credential-file for deployment.
      console.log(JSON.stringify(value, null, 2));
    }
  } else
    throw new Error(
      "Usage: migrate | status | provision <existing-node-UUID> <name> [node|gateway|operator] [platform] [group] [--credential-file <new-private-file>]",
    );
} finally {
  await db.end();
}
