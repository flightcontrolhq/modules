import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { compileAllDefinitions, CompileError, compileDefinitionFile } from "../src/compiler.js";

const fixturesDir = join(process.cwd(), "test", "fixtures", "compile");

describe("compiler", () => {
  it("compiles one definition file to canonical module config", async () => {
    const compiled = await compileDefinitionFile(join(fixturesDir, "modules", "networking", "vpc", "ravion-aws-vpc-definition.yml"));

    assert.equal(compiled.type, "ravion-aws-vpc");
    assert.equal(compiled.name, "AWS VPC");
    assert.equal(compiled.description, "AWS VPC and subnets");
    assert.equal(compiled.version, "1.2.3");
    assert.equal(compiled.releaseDescription, "Add subnet options.");
    assert.deepEqual(compiled.module, {
      inputs: [
        { id: "name", type: "string", label: "Name", required: true },
        { id: "environment", type: "string", label: "Environment", required: true },
        { id: "networking", type: "section", label: "Networking" },
        {
          id: "vpc",
          type: "stack",
          label: "VPC",
          outputs: {
            vpc_id: "VPC ID",
          },
        },
        {
          id: "advanced",
          type: "object",
          label: "Advanced",
          properties: {
            enabled: { type: "boolean", default: true },
          },
        },
      ],
      stack: {
        pipelines: {
          defaults: {
            variant: "standard",
            input: {
              source: {
                repo: "https://github.com/flightcontrolhq/modules",
                ref: "ravion-aws-vpc@1.2.3",
                base_path: "networking/vpc",
              },
            },
          },
          change: { pipeline_id: "terraform-change" },
        },
        ravion_state_backend_workspace: "<< module.given_id >>",
        type: "opentofu",
        source: {
          repo: "https://github.com/flightcontrolhq/modules",
          ref: "ravion-aws-vpc@1.2.3",
          base_path: "networking/vpc",
        },
      },
      deploy: {
        strategy: "rolling",
      },
      settings: {
        advanced: {
          retries: 2,
        },
      },
    });
  });

  it("compiles all colocated definitions under module category directories", async () => {
    const compiled = await compileAllDefinitions(join(fixturesDir, "modules"));

    assert.deepEqual(compiled.map((definition) => definition.type), ["ravion-aws-cluster", "ravion-aws-vpc"]);
  });

  it("fails when a local token remains after compilation", async () => {
    await assert.rejects(
      compileDefinitionFile(join(fixturesDir, "invalid-local-token.yml")),
      (error) => error instanceof CompileError && error.message.includes("module.stack.source.ref"),
    );
  });

  it("detects include cycles with a readable path chain", async () => {
    await assert.rejects(
      compileDefinitionFile(join(fixturesDir, "invalid-cycle.yml")),
      (error) => error instanceof CompileError && error.message.includes("include cycle detected") && error.message.includes("cycle-a.yml"),
    );
  });

  it("fails when a $with token is embedded in a template string", async () => {
    await assert.rejects(
      compileDefinitionFile(join(fixturesDir, "invalid-with-token.yml")),
      (error) => error instanceof CompileError && error.message.includes("$with tokens must occupy the entire string"),
    );
  });
});
