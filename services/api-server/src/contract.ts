import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { Ajv2020 } from "ajv/dist/2020.js";
import type { ContractV1 } from "@offgrid/shared-types";
export type Operation = ContractV1["Operation"];
export type Ack = ContractV1["Acknowledgment"];
export type PushResult = ContractV1["PushResult"];
export type Conflict = ContractV1["Conflict"];
export const CONTRACT_SHA = "d321ccbf0166a78aa6c07d8803167ebe640d8e3d";
const pin = JSON.parse(
  readFileSync(new URL("../contract-pin.json", import.meta.url), "utf8"),
);
const schemaBytes = readFileSync(
  new URL(
    "../../../packages/protocol/schemas/v1/contract.schema.json",
    import.meta.url,
  ),
);
if (
  pin.commit !== CONTRACT_SHA ||
  createHash("sha256").update(schemaBytes).digest("hex") !== pin.schemaSha256
)
  throw new Error("Pinned rc.2 schema mismatch; review before upgrading");
const schema = JSON.parse(schemaBytes.toString("utf8"));
// src/ and dist/ are equally deep inside services/api-server.
const ajv = new Ajv2020({ strict: true, allErrors: true });
ajv.addSchema(schema);
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public retryable = false,
  ) {
    super(message);
  }
}
export function validate<K extends keyof ContractV1>(
  name: K,
  value: unknown,
): ContractV1[K] {
  const check = ajv.getSchema(schema.$id + "#/$defs/" + name);
  if (!check || !check(value))
    throw new ApiError(422, "VALIDATION_ERROR", `Body does not match ${name}`);
  return value as ContractV1[K];
}
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object")
    return (
      "{" +
      Object.entries(value)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => JSON.stringify(k) + ":" + canonical(v))
        .join(",") +
      "}"
    );
  return JSON.stringify(value);
}
