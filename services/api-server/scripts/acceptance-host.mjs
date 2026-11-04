// Disposable CI host only. Never targets a team database or prints credentials.
import { pool, migrate, provision } from "../dist/database.js";
import { Engine } from "../dist/engine.js";
import { createHttp } from "../dist/http.js";
import { randomUUID } from "node:crypto";
import { writeFileSync } from "node:fs";
const url = process.env.TEST_DATABASE_URL;
if (!url || !new URL(url).pathname.endsWith("_test"))
  throw Error("Disposable _test database required");
const db = pool(url);
await migrate(db);
const engine = new Engine(db);
await engine.init();
const nodeA = randomUUID(),
  nodeB = randomUUID(),
  nodeC = randomUUID(),
  operatorId = randomUUID();
await provision(db, nodeA, "Acceptance sender");
await provision(db, nodeB, "Acceptance relay");
const gatewayCredential = await provision(
  db,
  nodeC,
  "Acceptance gateway",
  "gateway",
);
const operatorCredential = await provision(
  db,
  operatorId,
  "Acceptance operator",
  "operator",
  "Web",
);
const http = createHttp(engine, {
  origin: "http://127.0.0.1:4000",
  insecureLocal: true,
});
await new Promise((resolve) => http.server.listen(4000, "127.0.0.1", resolve));
writeFileSync(
  process.env.OFFGRID_ACCEPTANCE_CONFIG,
  JSON.stringify({
    nodeA,
    nodeB,
    nodeC,
    operatorId,
    gatewayCredential,
    operatorCredential,
    baseURL: "http://127.0.0.1:4000",
  }),
  { mode: 0o600, flag: "wx" },
);
console.log("Disposable acceptance host ready; credentials stored privately");
async function close() {
  await http.close();
  await db.end();
}
process.on("SIGTERM", () => void close());
process.on("SIGINT", () => void close());
