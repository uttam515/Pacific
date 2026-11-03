import { compile } from "json-schema-to-typescript";
import { readFile, writeFile } from "node:fs/promises";
const schema = JSON.parse(
  await readFile(
    new URL(
      "../packages/protocol/schemas/v1/contract.schema.json",
      import.meta.url,
    ),
    "utf8",
  ),
);
const model = {
  type: "object",
  properties: Object.fromEntries(
    Object.keys(schema.$defs).map((n) => [n, { $ref: "#/$defs/" + n }]),
  ),
  required: Object.keys(schema.$defs),
  additionalProperties: false,
  $defs: schema.$defs,
};
const text = await compile(model, "ContractV1", {
  bannerComment:
    "/* Generated from pinned rc.2 JSON Schema. Run pnpm contract:types; do not edit by hand. */",
  ignoreMinAndMaxItems: true,
});
const file = new URL(
  "../packages/shared-types/src/contract-v1.ts",
  import.meta.url,
);
if (process.argv.includes("--check")) {
  if ((await readFile(file, "utf8")) !== text)
    throw new Error("Contract types are stale");
} else await writeFile(file, text);
