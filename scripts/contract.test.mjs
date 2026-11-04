import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
const read = (path) =>
  JSON.parse(readFileSync(new URL("../" + path, import.meta.url), "utf8"));
const base = "packages/protocol/fixtures/v1/";
const schema = read("packages/protocol/schemas/v1/contract.schema.json");
const manifest = read(base + "manifest.json");
const ajv = new Ajv2020({ strict: true, allErrors: true });
ajv.addSchema(schema);
for (const [name, entry] of Object.entries(manifest.fixtures))
  test(`${entry.valid ? "accept" : "reject"} ${name}`, () => {
    const validator = ajv.getSchema(schema.$id + "#/$defs/" + entry.schema);
    assert.ok(validator, "Missing schema " + entry.schema);
    assert.equal(
      validator(read(base + name)),
      entry.valid,
      JSON.stringify(validator.errors),
    );
  });
test("every fixture is registered", () => {
  assert.deepEqual(
    readdirSync(new URL("../" + base, import.meta.url))
      .filter((x) => x.endsWith(".json") && x !== "manifest.json")
      .sort(),
    Object.keys(manifest.fixtures).sort(),
  );
});
test("duplicate upload receipt identifies the original commitment", () => {
  const a = read(base + "sync-push-response.json").results[0],
    b = read(base + "sync-push-duplicate-response.json").results[0];
  assert.equal(b.duplicate, true);
  assert.deepEqual(a.ack, b.ack);
  assert.equal(a.operationId, b.operationId);
  assert.equal(a.entityVersion, b.entityVersion);
});
test("packet and operation IDs differ and relay origin survives wrapping", () => {
  const p = read(base + "transport-operation.json");
  assert.notEqual(p.packetId, p.payload.operationId);
  assert.equal(
    p.payload.originNodeId,
    read(base + "operation-message.json").originNodeId,
  );
  assert.ok(p.ttl + p.hopCount <= 8);
});
test("peer receipt cannot be mistaken for backend commitment", () => {
  const p = read(base + "ack-peer.json"),
    b = read(base + "ack-backend.json");
  assert.equal(p.operationId, b.operationId);
  assert.equal(p.stage, "PEER_STORED");
  assert.equal(b.stage, "BACKEND_COMMITTED");
  assert.notEqual(p.ackId, b.ackId);
});
test("conflicting fixtures have distinct operations and the same base/entity", () => {
  const c = read(base + "conflict-open.json"),
    [a, b] = c.candidates.map((x) => x.operation);
  assert.notEqual(a.operationId, b.operationId);
  assert.equal(a.entityId, b.entityId);
  assert.equal(a.baseVersion, b.baseVersion);
  assert.equal(c.currentEntityVersion, a.baseVersion + 1);
});
test("resolution fixture selects an existing candidate with matching concurrency guards", () => {
  const c = read(base + "conflict-open.json"),
    q = read(base + "conflict-resolve-request.json"),
    r = read(base + "conflict-resolve-response.json");
  assert.ok(
    c.candidates.some((x) => x.operation.operationId === q.selectedOperationId),
  );
  assert.equal(q.expectedEntityVersion, c.currentEntityVersion);
  assert.equal(q.expectedConflictRevision, c.revision);
  assert.equal(r.conflict.currentEntityVersion, c.currentEntityVersion + 1);
  assert.deepEqual(r.conflict.candidates, c.candidates);
  assert.equal(r.ack.operationId, q.operationId);
});
test("snapshot compatibility state has real backend-receipt evidence in fixture", () => {
  const s = read(base + "dashboard-snapshot.json");
  for (const op of s.operations) {
    if (op.status === "synced") {
      assert.equal(op.delivery.backendReceipt.stage, "BACKEND_COMMITTED");
      assert.equal(op.delivery.backendReceipt.operationId, op.id);
    }
  }
});
test("every named schema compiles in strict Draft 2020-12 mode", () => {
  for (const name of Object.keys(schema.$defs))
    assert.ok(ajv.getSchema(schema.$id + "#/$defs/" + name));
});
