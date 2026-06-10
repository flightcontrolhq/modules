import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { AuthoringSchemaError, parseAuthoringDefinitionFile } from "../src/authoring-schema.js";

const fixturesDir = join(process.cwd(), "test", "fixtures");

describe("authoring schema", () => {
  it("accepts a valid definition and preserves canonical module data", async () => {
    const definition = await parseAuthoringDefinitionFile(join(fixturesDir, "valid-definition.yml"));

    assert.equal(definition.definition.type, "ravion-aws-vpc");
    assert.equal(definition.release.version, "1.2.3");
    assert.deepEqual(definition.module.inputs, [
      { id: "region", type: "string", label: "AWS Region", required: true, values: "$values:aws/regions.select" },
      { id: "settings", type: "object", label: "Settings", properties: { enabled: { type: "boolean", default: true } } },
    ]);
  });

  it("rejects missing metadata", async () => {
    await assert.rejects(
      parseAuthoringDefinitionFile(join(fixturesDir, "invalid-missing-metadata.yml")),
      (error) => hasIssue(error, "definition.name") && hasIssue(error, "release.description"),
    );
  });

  it("rejects invalid release versions", async () => {
    await assert.rejects(
      parseAuthoringDefinitionFile(join(fixturesDir, "invalid-release-version.yml")),
      (error) => hasIssue(error, "release.version"),
    );
  });

  it("rejects invalid source metadata", async () => {
    await assert.rejects(
      parseAuthoringDefinitionFile(join(fixturesDir, "invalid-source-metadata.yml")),
      (error) => hasIssue(error, "module.stack.source.ref"),
    );
  });

  it("accepts every composition directive shape", async () => {
    const definition = await parseAuthoringDefinitionFile(join(fixturesDir, "valid-directives.yml"));

    assert.ok(definition.module.inputs);
    assert.ok(definition.module.stack);
  });

  it("rejects invalid directive shapes", async () => {
    await assert.rejects(
      parseAuthoringDefinitionFile(join(fixturesDir, "invalid-directives.yml")),
      (error) =>
        hasIssue(error, "module.inputs[0].$include") &&
        hasIssue(error, "module.inputs[1].with") &&
        hasIssue(error, "module.stack.$merge"),
    );
  });
});

function hasIssue(error: unknown, path: string): boolean {
  assert.ok(error instanceof AuthoringSchemaError);
  return error.issues.some((issue) => issue.path === path);
}
