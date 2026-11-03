import { pool, migrate, provision } from "./database.js";
import type { Actor } from "./database.js";
const db = pool();
try {
  const [
    command,
    id,
    name,
    role = "node",
    platform = "iOS",
    group = "local-demo",
  ] = process.argv.slice(2);
  if (command === "migrate") {
    await migrate(db);
    console.log("Database migrations applied");
  } else if (command === "provision" && id && name) {
    const secret = await provision(
      db,
      id,
      name,
      role as Actor["role"],
      platform,
      group,
    );
    console.log(
      JSON.stringify(
        {
          nodeId: id,
          bearerCredential: secret,
          note: "Private credential; copy to device secure storage. Do not commit or share in chat.",
        },
        null,
        2,
      ),
    );
  } else
    throw new Error(
      "Usage: migrate | provision <node-UUID> <display-name> [node|gateway|operator] [platform] [group]",
    );
} finally {
  await db.end();
}
