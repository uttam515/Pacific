import test from "node:test";
import assert from "node:assert/strict";
import {
  demoSnapshot,
  applyDemoAction,
  toggleDemoGateway,
  isSnapshot,
} from "../src/domain.ts";
const action = (type: any, extra = {}) => ({
  type,
  operationId: "unique-op",
  createdAt: 1,
  ...extra,
});
test("initial demo is a valid snapshot; malformed API responses are rejected", () => {
  assert.equal(isSnapshot(demoSnapshot()), true);
  assert.equal(isSnapshot({ schemaVersion: 1 }), false);
  assert.equal(
    isSnapshot({ ...demoSnapshot(), alerts: [{ id: "bad" }] }),
    false,
  );
});
test("gateway failure selects a reachable alternative and preserves queued data", () => {
  const s = demoSnapshot();
  const next = toggleDemoGateway(s);
  assert.equal(next.gateways[0].reachable, false);
  assert.equal(next.gateways[1].selected, true);
  assert.deepEqual(next.operations, s.operations);
  assert.equal(s.gateways[0].reachable, true);
});
test("no gateway means sync keeps pending operations", () => {
  const s = demoSnapshot();
  s.gateways = s.gateways.map((g) => ({ ...g, reachable: false }));
  const next = applyDemoAction(s, action("RETRY_SYNC"));
  assert.deepEqual(next.operations, s.operations);
});
test("sync commits pending data without resolving conflicts", () => {
  const s = demoSnapshot();
  const next = applyDemoAction(s, action("RETRY_SYNC"));
  assert.equal(
    next.operations.some((o) => o.status === "queued"),
    false,
  );
  assert.equal(
    next.operations.filter((o) => o.status === "conflict").length,
    1,
  );
});
test("acknowledgment changes only the target alert", () => {
  const s = demoSnapshot();
  const next = applyDemoAction(s, action("ACK_ALERT", { entityId: "sos-001" }));
  assert.equal(next.alerts[0].status, "acknowledged");
  assert.deepEqual(next.alerts[1], s.alerts[1]);
});
test("resolution preserves both alternatives and unrelated conflicts", () => {
  const s = demoSnapshot();
  s.operations.push({
    ...s.operations[23],
    id: "other",
    conflictId: "other-conflict",
  });
  const next = applyDemoAction(
    s,
    action("RESOLVE_CONFLICT", { entityId: "conflict-01", choice: "right" }),
  );
  assert.equal(next.conflicts[0].resolved, "right");
  assert.equal(next.conflicts[0].left, s.conflicts[0].left);
  assert.equal(next.operations.at(-1)?.status, "conflict");
});
test("announcements are queued, not marked synchronized", () => {
  const next = applyDemoAction(
    demoSnapshot(),
    action("CREATE_ANNOUNCEMENT", { text: "Shelter open" }),
  );
  assert.equal(next.operations[0].id, "unique-op");
  assert.equal(next.operations[0].status, "queued");
});
