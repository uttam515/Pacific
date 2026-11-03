import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { WebSocket } from "ws";
import { pool, migrate, provision } from "../src/database.js";
import { Engine } from "../src/engine.js";
import { createHttp } from "../src/http.js";
import { validate } from "../src/contract.js";
const f = (name: string) =>
  JSON.parse(
    readFileSync(
      new URL(
        "../../../packages/protocol/fixtures/v1/" + name,
        import.meta.url,
      ),
      "utf8",
    ),
  );
const A = "00000000-0000-4000-8000-000000000001",
  B = "00000000-0000-4000-8000-000000000002",
  O = "00000000-0000-4000-8000-000000000004",
  C = "00000000-0000-4000-8000-000000000005";
test("real PostgreSQL and HTTP integration", async (t) => {
  const url = process.env.TEST_DATABASE_URL;
  if (!url || !new URL(url).pathname.endsWith("_test"))
    throw new Error(
      "TEST_DATABASE_URL must identify a disposable database ending in _test",
    );
  const db = pool(url);
  const engine = new Engine(db);
  const options = { origin: "http://127.0.0.1", insecureLocal: true };
  const http = createHttp(engine, options);
  let base = "",
    a = "",
    b = "",
    op = "",
    other = "";
  try {
    const version = (await db.query("SELECT version() AS v")).rows[0].v;
    assert.match(version, /PostgreSQL/);
    console.log("Testing database engine:", version.split(" on ")[0]);
    await migrate(db);
    await migrate(db);
    await db.query(
      "TRUNCATE nodes,credentials,entities,operations,acknowledgments,conflicts,changes RESTART IDENTITY CASCADE",
    );
    await db.query("UPDATE commit_clock SET lamport=0");
    await engine.init();
    a = await provision(db, A, "iPhone A");
    b = await provision(db, B, "iPhone B");
    op = await provision(db, O, "Operator", "operator", "Web");
    other = await provision(db, C, "Other group", "node", "iOS", "other");
    await new Promise<void>((resolve) =>
      http.server.listen(0, "127.0.0.1", resolve),
    );
    const address = http.server.address();
    if (!address || typeof address === "string")
      throw new Error("No listening address");
    base = `http://127.0.0.1:${address.port}`;
    options.origin = base;
    const request = async (
      path: string,
      credential = a,
      body?: unknown,
      headers: Record<string, string> = {},
    ) => {
      const r = await fetch(base + "/api/v1" + path, {
        method: body === undefined ? "GET" : "POST",
        headers: {
          Authorization: "Bearer " + credential,
          "Content-Type": "application/json",
          ...headers,
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      return { status: r.status, json: await r.json() };
    };
    const fresh = () => ({
      ...f("operation-message.json"),
      operationId: randomUUID(),
      entityId: randomUUID(),
    });
    const push = (
      operation: unknown,
      credential = a,
      nodeId = A,
      headers = {},
    ) =>
      request(
        "/sync/push",
        credential,
        { schemaVersion: 1, nodeId, operations: [operation] },
        headers,
      );
    await t.test(
      "private credential file and migration-status CLI",
      async () => {
        const directory = mkdtempSync(join(tmpdir(), "offgrid-provision-"));
        const file = join(directory, "device.json");
        const id = randomUUID();
        const cwd = fileURLToPath(new URL("../", import.meta.url));
        const run = (args: string[]) =>
          spawnSync(
            process.execPath,
            ["--import", "tsx", "src/cli.ts", ...args],
            {
              cwd,
              encoding: "utf8",
              env: { ...process.env, DATABASE_URL: url },
            },
          );
        try {
          const first = run([
            "provision",
            id,
            "Private file test",
            "node",
            "iOS",
            "--credential-file",
            file,
          ]);
          assert.equal(first.status, 0, first.stderr);
          const stored = JSON.parse(readFileSync(file, "utf8"));
          assert.equal(stored.nodeId, id);
          assert.equal(statSync(file).mode & 0o777, 0o600);
          assert.equal(first.stdout.includes(stored.bearerCredential), false);
          assert.equal(JSON.parse(first.stdout).credentialPrinted, false);
          const again = run([
            "provision",
            id,
            "Private file test",
            "node",
            "iOS",
            "--credential-file",
            file,
          ]);
          assert.notEqual(again.status, 0);
          assert.equal(
            JSON.parse(readFileSync(file, "utf8")).bearerCredential,
            stored.bearerCredential,
          );
          const active = await db.query(
            "SELECT count(*)::int AS n FROM credentials WHERE node_id=$1 AND NOT revoked",
            [id],
          );
          assert.equal(active.rows[0].n, 1);
          const status = run(["status"]);
          assert.equal(status.status, 0, status.stderr);
          const report = JSON.parse(status.stdout);
          assert.equal(report.requiredTables, "verified");
          assert.ok(
            report.migrations.some((x: any) => x.name === "001_backend.sql"),
          );
        } finally {
          rmSync(directory, { recursive: true, force: true });
        }
      },
    );
    await t.test("migration, auth and node binding", async () => {
      assert.equal((await request("/health", "")).status, 200);
      assert.equal((await request("/sync/pull", "")).status, 401);
      assert.equal((await push(fresh(), a, B)).status, 403);
      const operation = fresh();
      operation.originNodeId = B;
      const denied = await push(operation);
      assert.equal(denied.json.results[0].outcome, "REJECTED");
      assert.equal(denied.json.results[0].error.code, "FORBIDDEN");
      const records = await db.query("SELECT token_hash FROM credentials");
      assert.ok(records.rows.every((r) => /^[0-9a-f]{64}$/.test(r.token_hash)));
    });
    await t.test(
      "fixture push commits once and snapshot exposes actual data",
      async () => {
        const operation = f("operation-message.json");
        const first = await push(operation);
        assert.equal(first.status, 200);
        validate("PushResponse", first.json);
        assert.equal(first.json.results[0].duplicate, false);
        const again = await push(operation);
        assert.equal(again.json.results[0].duplicate, true);
        assert.deepEqual(again.json.results[0].ack, first.json.results[0].ack);
        const snapshot = await request("/dashboard/snapshot", op);
        assert.equal(snapshot.status, 200);
        validate("DashboardSnapshot", snapshot.json);
        assert.equal(
          snapshot.json.operations.find(
            (x: any) => x.id === operation.operationId,
          ).status,
          "synced",
        );
        assert.equal(
          (
            await db.query(
              "SELECT count(*)::int AS n FROM entities WHERE entity_id=$1",
              [operation.entityId],
            )
          ).rows[0].n,
          1,
        );
        assert.equal((await request("/dashboard/snapshot", a)).status, 403);
      },
    );
    await t.test(
      "concurrent identical uploads have exactly one effect and stable ACK",
      async () => {
        const operation = fresh();
        const responses = await Promise.all(
          Array.from({ length: 12 }, () => push(operation)),
        );
        assert.ok(responses.every((r) => r.status === 200));
        assert.equal(
          responses.filter((r) => !r.json.results[0].duplicate).length,
          1,
        );
        assert.equal(
          new Set(responses.map((r) => r.json.results[0].ack.ackId)).size,
          1,
        );
        assert.equal(
          (
            await db.query(
              "SELECT count(*)::int AS n FROM operations WHERE operation_id=$1",
              [operation.operationId],
            )
          ).rows[0].n,
          1,
        );
        assert.equal(
          (
            await db.query(
              "SELECT count(*)::int AS n FROM changes WHERE body->'operation'->>'operationId'=$1",
              [operation.operationId],
            )
          ).rows[0].n,
          1,
        );
      },
    );
    await t.test(
      "same ID with changed content is rejected without effects",
      async () => {
        const operation = fresh();
        await push(operation);
        operation.payload.text = "Changed after commit";
        const reuse = await push(operation);
        assert.equal(reuse.json.results[0].error.code, "ID_REUSE");
        const row = (
          await db.query(
            "SELECT operation FROM operations WHERE operation_id=$1",
            [operation.operationId],
          )
        ).rows[0];
        assert.notEqual(row.operation.payload.text, operation.payload.text);
      },
    );
    await t.test(
      "a dropped HTTP response after commit is safe to retry",
      async () => {
        const operation = fresh();
        const drop = (req: any, res: any) => {
          if (req.headers["x-test-drop-response"] === "yes") {
            res.end = () => {
              req.socket.destroy();
              return res;
            };
          }
        };
        http.server.prependListener("request", drop);
        try {
          await assert.rejects(() =>
            push(operation, a, A, { "x-test-drop-response": "yes" }),
          );
          const retry = await push(operation);
          assert.equal(retry.status, 200);
          assert.equal(retry.json.results[0].duplicate, true);
        } finally {
          http.server.removeListener("request", drop);
        }
      },
    );
    await t.test(
      "cursor paging, empty polling and late uploads do not skip effects",
      async () => {
        const first = await request("/sync/pull?cursor=c0&limit=1");
        validate("PullResponse", first.json);
        assert.equal(first.json.hasMore, true);
        let cursor = first.json.nextCursor;
        let next;
        do {
          next = await request("/sync/pull?cursor=" + cursor);
          cursor = next.json.nextCursor;
        } while (next.json.hasMore);
        assert.equal(
          (await request("/sync/pull?cursor=" + cursor)).json.changes.length,
          0,
        );
        const late = fresh();
        late.timestamp = 1;
        await push(late);
        const newer = await request("/sync/pull?cursor=" + cursor);
        assert.ok(
          newer.json.changes.some(
            (x: any) => x.operation?.operationId === late.operationId,
          ),
        );
        const hidden = await request("/sync/pull?cursor=c0", other);
        assert.equal(hidden.json.changes.length, 0);
        assert.equal(
          (await request("/sync/pull?cursor=not-a-cursor")).status,
          400,
        );
      },
    );
    await t.test(
      "conflicts preserve edits, reject stale resolution and resolve idempotently",
      async () => {
        for (const name of [
          "announcement-create.json",
          "announcement-edit-a.json",
        ])
          assert.equal(
            (await push(f(name))).json.results[0].outcome,
            "COMMITTED",
          );
        const competing = f("announcement-edit-b.json");
        const conflictPush = await push(competing, b, B);
        assert.equal(conflictPush.json.results[0].outcome, "CONFLICT");
        const id = conflictPush.json.results[0].conflictId;
        const conflict = await request("/conflicts/" + id);
        validate("Conflict", conflict.json);
        assert.equal(conflict.json.candidates.length, 2);
        const body = {
          ...f("conflict-resolve-request.json"),
          expectedConflictRevision: conflict.json.revision,
          expectedEntityVersion: conflict.json.currentEntityVersion,
        };
        assert.equal(
          (await request("/conflicts/" + id + "/resolve", a, body)).status,
          403,
        );
        assert.equal(
          (
            await request("/conflicts/" + id + "/resolve", op, {
              ...body,
              expectedEntityVersion: 99,
            })
          ).status,
          409,
        );
        const resolved = await request(
          "/conflicts/" + id + "/resolve",
          op,
          body,
        );
        assert.equal(resolved.status, 200);
        validate("ResolveResponse", resolved.json);
        assert.equal(resolved.json.conflict.currentEntityVersion, 3);
        assert.deepEqual(
          resolved.json.conflict.candidates,
          conflict.json.candidates,
        );
        assert.equal(
          (await request("/conflicts/" + id + "/resolve", op, body)).json
            .duplicate,
          true,
        );
        assert.equal(
          (
            await request("/conflicts/" + id + "/resolve", op, {
              ...body,
              operationId: randomUUID(),
            })
          ).status,
          409,
        );
        assert.equal(
          (await push(competing, b, B)).json.results[0].duplicate,
          true,
        );
      },
    );
    await t.test(
      "recipient receipts require authorized nodes and reject forged backend ACKs",
      async () => {
        const body = f("receipt-request.json");
        assert.equal((await request("/receipts", a, body)).status, 403);
        const ok = await request("/receipts", b, body);
        assert.equal(ok.status, 200);
        assert.equal(
          (await request("/receipts", b, body)).json.duplicate,
          true,
        );
        const forged = {
          schemaVersion: 1,
          nodeId: B,
          ack: { ...f("ack-backend.json"), acknowledgingNodeId: B },
        };
        assert.equal((await request("/receipts", b, forged)).status, 403);
      },
    );
    await t.test(
      "WebSocket notifications arrive after durable PostgreSQL commitment",
      async () => {
        const ws = new WebSocket(base.replace("http:", "ws:") + "/ws", {
          headers: { Authorization: "Bearer " + a },
        });
        await new Promise<void>((resolve, reject) => {
          ws.once("open", resolve);
          ws.once("error", reject);
        });
        const operation = fresh();
        const notified = new Promise<void>((resolve, reject) => {
          const timer = setTimeout(() => {
            ws.terminate();
            reject(new Error("No committed notification"));
          }, 5000);
          ws.on("message", async (raw) => {
            try {
              validate("Notification", JSON.parse(raw.toString()));
              const row = await db.query(
                "SELECT 1 FROM operations WHERE operation_id=$1",
                [operation.operationId],
              );
              if (row.rowCount) {
                clearTimeout(timer);
                resolve();
              }
            } catch (e) {
              clearTimeout(timer);
              reject(e);
            }
          });
        });
        await push(operation);
        await notified;
        ws.close();
      },
    );
    await t.test(
      "operator cookie session and same-origin checks work",
      async () => {
        const login = await request(
          "/operator/session",
          op,
          {},
          { Origin: base },
        );
        assert.equal(login.status, 200);
        const raw = await fetch(base + "/api/v1/operator/session", {
          method: "POST",
          headers: {
            Authorization: "Bearer " + op,
            Origin: base,
            "Content-Type": "application/json",
          },
          body: "{}",
        });
        const session = raw.headers.get("set-cookie")!.split(";")[0];
        assert.match(session, /offgrid_session=/);
        assert.match(raw.headers.get("set-cookie")!, /HttpOnly/i);
        const snap = await fetch(base + "/api/v1/dashboard/snapshot", {
          headers: { Cookie: session },
        });
        assert.equal(snap.status, 200);
        const cross = await fetch(base + "/api/v1/receipts", {
          method: "POST",
          headers: {
            Cookie: session,
            Origin: "https://evil.invalid",
            "Content-Type": "application/json",
          },
          body: "{}",
        });
        assert.equal(cross.status, 403);
      },
    );
    await t.test(
      "reconnecting a new database pool preserves commitment and duplicate ACK",
      async () => {
        const operation = fresh(),
          first = await push(operation);
        const another = pool(url);
        try {
          const e = new Engine(another);
          const actor = {
            node_id: A,
            group_id: "local-demo",
            role: "node" as const,
            kind: "bearer" as const,
          };
          const retry = await e.push(actor, {
            schemaVersion: 1,
            nodeId: A,
            operations: [operation],
          });
          assert.equal(retry.results[0].outcome, "COMMITTED");
          assert.equal((retry.results[0] as any).duplicate, true);
          assert.deepEqual(
            (retry.results[0] as any).ack,
            first.json.results[0].ack,
          );
        } finally {
          await another.end();
        }
      },
    );
    await t.test("invalid fixtures cannot create records", async () => {
      const invalid = f("sync-push-request.json");
      invalid.operations[0] = f("invalid-operation-string-payload.json");
      assert.equal((await request("/sync/push", a, invalid)).status, 422);
    });
  } finally {
    if (http.server.listening) await http.close();
    await db.end();
  }
});
