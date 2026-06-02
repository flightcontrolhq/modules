import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ModuleSchemaError, validateModuleConfig } from "../src/module-schema.js";

describe("canonical module schema", () => {
  it("accepts compiled current Flightcontrol module shapes", () => {
    const module = validateModuleConfig({
      inputs: [
        { id: "name", type: "string", label: "Name", required: true },
        { id: "networking", type: "section", label: "Networking" },
        { id: "settings", type: "object", label: "Settings", properties: { enabled: { type: "boolean", default: true } } },
        { id: "tags", type: "object_map", label: "Tags" },
        { id: "subnets", type: "object_array", label: "Subnets" },
        { id: "repository", type: "gitrepo", label: "Repository" },
        { id: "environment", type: "keyvalue", label: "Environment" },
        { id: "stack", type: "stack", label: "Stack" },
        { id: "build", type: "build", label: "Build" },
        { id: "deploy", type: "deploy", label: "Deploy" },
      ],
      stack: { type: "opentofu", ravion_state_backend_workspace: "<< module.given_id >>" },
      build: { type: "nixpacks" },
      deploy: { strategy: "rolling" },
      ui: { links: [{ name: "Console", href: "<< output.console_url >>" }] },
      output: { bucket_name: "<< stack.output.bucket_name >>" },
    });

    assert.equal(Array.isArray(module.inputs), true);
  });

  it("rejects duplicate input IDs", () => {
    assert.throws(
      () =>
        validateModuleConfig({
          inputs: [
            { id: "region", type: "string", label: "Region" },
            { id: "region", type: "string", label: "Region again" },
          ],
        }),
      (error) => hasIssue(error, "inputs[1].id"),
    );
  });

  it("rejects unsupported input types", () => {
    assert.throws(
      () => validateModuleConfig({ inputs: [{ id: "legacy", type: "legacy", label: "Legacy" }] }),
      (error) => hasIssue(error, "inputs[0].type"),
    );
  });

  it("rejects old input.properties.validation shapes", () => {
    assert.throws(
      () =>
        validateModuleConfig({
          inputs: [
            {
              id: "settings",
              type: "object",
              label: "Settings",
              properties: {
                validation: { pattern: "^[a-z]+$", message: "Use lowercase letters." },
              },
            },
          ],
        }),
      (error) => hasIssue(error, "inputs[0].properties.validation"),
    );
  });
});

function hasIssue(error: unknown, path: string): boolean {
  assert.ok(error instanceof ModuleSchemaError);
  return error.issues.some((issue) => issue.path === path);
}
