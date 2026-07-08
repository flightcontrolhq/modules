import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { compileAllDefinitions, CompileError, compileDefinitionFile } from "../src/compiler.js";

const fixturesDir = join(process.cwd(), "test", "fixtures", "compile");
const repoRoot = resolve(process.cwd(), "../..");

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
      readme: "Terraform source https://github.com/flightcontrolhq/modules/tree/ravion-aws-vpc@1.2.3/networking/vpc",
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

  it("compiles Railpack inputs and builder object for ECS image builds", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "ecs_service", "rvn-ecs-web-definition.yml"));
    const inputs = getModuleInputs(compiled.module);

    assert.deepEqual(getValueOptions(findInput(inputs, "build_type")), ["dockerfile", "railpack", "prebuilt_image"]);
    assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, "source_repo")), ["dockerfile", "railpack", "nixpacks"]);

    const basePath = findInput(inputs, "source_base_path");
    assert.equal(basePath.label, "Source base path");
    assert.deepEqual(getBuildTypeShowWhen(basePath), ["dockerfile", "railpack", "nixpacks"]);

    const railpackVersion = findInput(inputs, "railpack_version");
    assert.equal(railpackVersion.label, "Railpack version");
    assert.deepEqual(getBuildTypeShowWhen(railpackVersion), ["railpack", "nixpacks"]);
    assert.deepEqual(railpackVersion.patterns, [
      {
        message: "Leave blank, use latest, a semantic version like 0.29.0, or a v-prefixed version like v0.29.0.",
        pattern: "^(|latest|v?[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)$",
      },
    ]);

    for (const inputId of ["railpack_install_cmd", "railpack_build_cmd", "railpack_start_cmd"]) {
      assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, inputId)), ["railpack", "nixpacks"]);
    }

    assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, "section_builder_config")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, "section_ecr")), ["dockerfile", "railpack", "nixpacks"]);

    const build = getModuleBuild(compiled.module);
    const builder = assertString(build.builder);
    assert.match(builder, /module\.input\.build_type == "railpack"/);
    assert.match(builder, /module\.input\.build_type == "nixpacks"/);
    assert.match(builder, /\{type: "railpack", railpack_version:/);
    assert.match(builder, /railpack_install_cmd: module\.input\.railpack_install_cmd/);
    assert.match(builder, /railpack_build_cmd: module\.input\.railpack_build_cmd/);
    assert.match(builder, /railpack_start_cmd:\s+module\.input\.railpack_start_cmd/);
    assert.match(builder, /cache_from: \{tag: "railpack"\}/);

    const railpackBranch = builder.slice(builder.indexOf('module.input.build_type == "railpack"'), builder.indexOf(': {type: "disabled"}'));
    assert.doesNotMatch(railpackBranch, /nixpacks_/);
    assert.doesNotMatch(railpackBranch, /build_path/);

    const ecrRepositoryCreationEnabled = getEcsTerraformVariable(compiled.module, "ecr_repository_creation_enabled");
    assert.equal(
      ecrRepositoryCreationEnabled,
      '<< module.input.build_type == "dockerfile" || module.input.build_type == "railpack" || module.input.build_type == "nixpacks" >>',
    );
  });

  it("compiles Railpack inputs and builder object for static builds", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "hosting", "static_site", "rvn-aws-static-definition.yml"));
    const inputs = getModuleInputs(compiled.module);

    assert.deepEqual(getValueOptions(findInput(inputs, "build_type")), ["railpack", "dockerfile", "none"]);
    assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, "source_repo")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, "output_directory")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, "build_environment_variables")), ["dockerfile", "railpack", "nixpacks"]);

    for (const inputId of ["railpack_version", "railpack_install_cmd", "railpack_build_cmd"]) {
      assert.deepEqual(getBuildTypeShowWhen(findInput(inputs, inputId)), ["railpack", "nixpacks"]);
    }
    assert.equal(inputs.some((input) => input.id === "railpack_start_cmd"), false);

    const build = getModuleBuild(compiled.module);
    const builder = assertString(build.builder);
    assert.match(builder, /module\.input\.build_type == "railpack"/);
    assert.match(builder, /module\.input\.build_type == "nixpacks"/);
    assert.match(builder, /\{type: "railpack", railpack_version:/);
    assert.match(builder, /railpack_install_cmd: module\.input\.railpack_install_cmd/);
    assert.match(builder, /railpack_build_cmd: module\.input\.railpack_build_cmd/);
    assert.match(builder, /output_directory: module\.input\.output_directory/);
    assert.doesNotMatch(builder, /railpack_start_cmd/);
    assert.doesNotMatch(builder, /cache_from: \{tag: "railpack"\}/);
  });
});

function getModuleInputs(module: Record<string, unknown>): Record<string, unknown>[] {
  const inputs = module.inputs;
  assert.ok(Array.isArray(inputs), "module.inputs should be an array");
  return inputs.map((input) => {
    assert.ok(isRecord(input), "module input should be an object");
    return input;
  });
}

function getModuleBuild(module: Record<string, unknown>): Record<string, unknown> {
  assert.ok(isRecord(module.build), "module.build should be an object");
  return module.build;
}

function findInput(inputs: Record<string, unknown>[], id: string): Record<string, unknown> {
  const input = inputs.find((candidate) => candidate.id === id);
  assert.ok(input, `expected input ${id}`);
  return input;
}

function getValueOptions(input: Record<string, unknown>): unknown[] {
  const values = input.values;
  assert.ok(Array.isArray(values), `${String(input.id)} should have values`);
  return values.map((value) => {
    assert.ok(isRecord(value), "value option should be an object");
    return value.value;
  });
}

function getBuildTypeShowWhen(input: Record<string, unknown>): unknown {
  const showWhen = assertRecord(input.show_when, `${String(input.id)}.show_when`);
  return showWhen.build_type;
}

function getEcsTerraformVariable(module: Record<string, unknown>, key: string): unknown {
  const stack = assertRecord(module.stack, "module.stack");
  const pipelines = assertRecord(stack.pipelines, "module.stack.pipelines");
  const defaults = assertRecord(pipelines.defaults, "module.stack.pipelines.defaults");
  const input = assertRecord(defaults.input, "module.stack.pipelines.defaults.input");
  const terraformVariables = assertRecord(input.terraform_variables, "module.stack.pipelines.defaults.input.terraform_variables");
  return terraformVariables[key];
}

function assertString(value: unknown): string {
  if (typeof value !== "string") {
    assert.fail("expected string");
  }
  return value;
}

function assertRecord(value: unknown, name: string): Record<string, unknown> {
  assert.ok(isRecord(value), `${name} should be an object`);
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
