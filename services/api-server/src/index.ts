import { pool } from "./database.js";
import { Engine } from "./engine.js";
import { createHttp } from "./http.js";
const db = pool(),
  engine = new Engine(db, process.env.BACKEND_NODE_ID);
await engine.init();
const port = Number(process.env.PORT || 4000),
  origin = process.env.DASHBOARD_ORIGIN || `http://localhost:${port}`;
if (!Number.isInteger(port) || port < 1 || port > 65535)
  throw new Error("Invalid PORT");
if (!origin.startsWith("https://") && process.env.ALLOW_INSECURE_LOCAL !== "1")
  throw new Error(
    "HTTPS origin required, or explicitly set ALLOW_INSECURE_LOCAL=1 for trusted local testing",
  );
const app = createHttp(engine, {
  origin,
  insecureLocal: process.env.ALLOW_INSECURE_LOCAL === "1",
});
app.server.listen(port, process.env.HOST || "127.0.0.1", () =>
  console.log(
    `OFFGRID backend listening on port ${port}; contract ${app.contractSha}`,
  ),
);
async function stop() {
  await app.close();
  await db.end();
}
process.on("SIGINT", () => void stop());
process.on("SIGTERM", () => void stop());
