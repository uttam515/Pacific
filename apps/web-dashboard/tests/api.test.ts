import test from "node:test";
import assert from "node:assert/strict";
import { fetchSnapshot, sendAction } from "../src/api.ts";
const c = { apiUrl: "https://test.invalid/api/v1", wsUrl: "" };
const a = {
  operationId: "fixed-id",
  type: "ACK_ALERT" as const,
  entityId: "sos-001",
  createdAt: 1,
};
test("server acknowledgment must match the queued action", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ acceptedOperationId: "wrong-id" }));
    await assert.rejects(() => sendAction(c, a), /remains queued/);
  } finally {
    globalThis.fetch = original;
  }
});
test("retry transmits the stable idempotency key and accepts a matching acknowledgment", async () => {
  const original = globalThis.fetch;
  const ids: string[] = [];
  try {
    globalThis.fetch = async (_input, init) => {
      ids.push((init?.headers as Record<string, string>)["Idempotency-Key"]);
      return new Response(JSON.stringify({ acceptedOperationId: "fixed-id" }));
    };
    await sendAction(c, a);
    await sendAction(c, a);
    assert.deepEqual(ids, ["fixed-id", "fixed-id"]);
  } finally {
    globalThis.fetch = original;
  }
});
test("HTTP failures cannot be acknowledged", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response("failure", { status: 503 });
    await assert.rejects(() => sendAction(c, a), /503/);
  } finally {
    globalThis.fetch = original;
  }
});
test("malformed live snapshots are rejected", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response(JSON.stringify({ nodes: [] }));
    await assert.rejects(() => fetchSnapshot(c), /contract/);
  } finally {
    globalThis.fetch = original;
  }
});
