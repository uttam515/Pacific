import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { canonical, validate, CONTRACT_SHA } from "../src/contract.js";
import { parseCursor } from "../src/engine.js";
const fixture = (name: string) =>
  JSON.parse(
    readFileSync(
      new URL(
        "../../../packages/protocol/fixtures/v1/" + name,
        import.meta.url,
      ),
      "utf8",
    ),
  );
test("wire schema is the pinned rc.2 contract", () => {
  assert.equal(CONTRACT_SHA, "d321ccbf0166a78aa6c07d8803167ebe640d8e3d");
  const f = fixture("sync-push-request.json");
  assert.deepEqual(validate("PushRequest", f), f);
});
test("string payload and missing backend version are rejected", () => {
  assert.throws(() =>
    validate("Operation", fixture("invalid-operation-string-payload.json")),
  );
  assert.throws(() =>
    validate(
      "Acknowledgment",
      fixture("invalid-backend-ack-missing-version.json"),
    ),
  );
});
test("idempotence comparison ignores JSON key order, not content", () => {
  assert.equal(
    canonical({ b: 2, a: { d: 4, c: 3 } }),
    canonical({ a: { c: 3, d: 4 }, b: 2 }),
  );
  assert.notEqual(canonical({ text: "a" }), canonical({ text: "b" }));
});
test("cursor is parsed losslessly and bounded to PostgreSQL bigint", () => {
  assert.equal(parseCursor("c9007199254740993"), "9007199254740993");
  assert.throws(() => parseCursor("c9223372036854775808"));
  assert.throws(() => parseCursor("42"));
});
