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
