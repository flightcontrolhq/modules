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

    assert.deepEqual(getValueOptions(findInput(inputs, "build_source")), ["dockerfile", "railpack", "image_registry"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "source_repo")), ["dockerfile", "railpack"]);

    const basePath = findInput(inputs, "source_base_path");
    assert.equal(basePath.label, "Source base path");
    assert.deepEqual(getBuildSourceShowWhen(basePath), ["dockerfile", "railpack"]);

    const railpackVersion = findInput(inputs, "railpack_version");
    assert.equal(railpackVersion.label, "Railpack version");
    assert.equal(getBuildSourceShowWhen(railpackVersion), "railpack");
    assert.deepEqual(railpackVersion.patterns, [
      {
        message: "Leave blank, use latest, a semantic version like 0.29.0, or a v-prefixed version like v0.29.0.",
        pattern: "^(|latest|v?[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)$",
      },
    ]);

    for (const inputId of ["railpack_install_cmd", "railpack_build_cmd", "railpack_start_cmd"]) {
      assert.equal(getBuildSourceShowWhen(findInput(inputs, inputId)), "railpack");
    }

    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "section_builder_config")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "section_ecr")), ["dockerfile", "railpack", "nixpacks"]);

    const build = getModuleBuild(compiled.module);
    const builder = assertString(build.builder);
    assert.match(builder, /module\.input\.build_source == "railpack"/);
    assert.match(builder, /module\.input\.build_source == "nixpacks"/);
    assert.match(builder, /\{type: "railpack", railpack_version:/);
    assert.match(builder, /install_cmd: module\.input\.railpack_install_cmd/);
    assert.match(builder, /build_cmd: module\.input\.railpack_build_cmd/);
    assert.match(builder, /start_cmd:\s+module\.input\.railpack_start_cmd/);
    assert.match(builder, /cache_from: \{tag: "railpack"\}/);

    const railpackBranch = builder.slice(builder.indexOf('module.input.build_source == "railpack"'), builder.indexOf(': {type: "disabled"}'));
    assert.doesNotMatch(railpackBranch, /nixpacks_/);
    assert.doesNotMatch(railpackBranch, /build_path/);

    const ecrRepositoryCreationEnabled = getEcsTerraformVariable(compiled.module, "ecr_repository_creation_enabled");
    assert.equal(
      ecrRepositoryCreationEnabled,
      '<< module.input.build_source == "dockerfile" || module.input.build_source == "railpack" || module.input.build_source == "nixpacks" >>',
    );
  });

  it("compiles Railpack inputs and builder object for static builds", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "hosting", "static_site", "rvn-aws-static-definition.yml"));
    const inputs = getModuleInputs(compiled.module);

    assert.deepEqual(getValueOptions(findInput(inputs, "build_source")), ["railpack", "dockerfile", "s3_directory"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "source_repo")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "output_directory")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "build_environment_variables")), ["dockerfile", "railpack", "nixpacks"]);

    for (const inputId of ["railpack_version", "railpack_install_cmd", "railpack_build_cmd"]) {
      assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, inputId)), ["railpack", "nixpacks"]);
    }
    assert.equal(inputs.some((input) => input.id === "railpack_start_cmd"), false);

    const build = getModuleBuild(compiled.module);
    const builder = assertString(build.builder);
    assert.match(builder, /module\.input\.build_source == "railpack"/);
    assert.match(builder, /module\.input\.build_source == "nixpacks"/);
    assert.match(builder, /\{type: "railpack", railpack_version:/);
    assert.match(builder, /install_cmd: module\.input\.railpack_install_cmd/);
    assert.match(builder, /build_cmd: module\.input\.railpack_build_cmd/);
    assert.match(builder, /output_directory: module\.input\.output_directory/);
    assert.doesNotMatch(builder, /start_cmd/);
    assert.doesNotMatch(builder, /cache_from: \{tag: "railpack"\}/);
  });

  it("compiles EC2 service load balancer source choices", async () => {
    const compiled = await compileDefinitionFile(
      join(repoRoot, "compute", "ec2_service", "rvn-ec2-service-definition.yml"),
    );
    const inputs = getModuleInputs(compiled.module);

    assert.equal(compiled.type, "rvn-ec2-service");

    const imageRef = findInput(getDeployInputs(compiled.module), "image_ref");
    assert.deepEqual(imageRef.patterns, [
      {
        message: "Image tags and digests must not contain whitespace.",
        pattern: "^\\S+$",
      },
    ]);

    const loadBalancerSource = findInput(inputs, "load_balancer_source");
    assert.equal(loadBalancerSource.default, "standalone_alb");
    assert.equal(loadBalancerSource.immutable, true);
    assert.deepEqual(getValueOptions(loadBalancerSource), ["standalone_alb", "ecs_cluster"]);
    assert.deepEqual(loadBalancerSource.show_when, { web_service_enabled: true });

    const standaloneAlb = findInput(inputs, "alb");
    assert.equal(standaloneAlb.required, true);
    assert.deepEqual(standaloneAlb.show_when, {
      web_service_enabled: true,
      load_balancer_source: "standalone_alb",
    });

    const ecsCluster = findInput(inputs, "ecs_cluster");
    assert.equal(ecsCluster.required, true);
    assert.equal(ecsCluster.immutable, true);
    assert.deepEqual(ecsCluster.show_when, {
      web_service_enabled: true,
      load_balancer_source: "ecs_cluster",
    });
    const clusterMappedInputs = ecsCluster.mapped_inputs;
    assert.ok(Array.isArray(clusterMappedInputs), "ecs_cluster.mapped_inputs should be an array");
    const clusterMappedInputIds = clusterMappedInputs.map((input) => assertRecord(input, "ECS cluster mapped input").id);
    for (const inputId of [
      "public_alb_http_listener_arn",
      "public_alb_https_listener_arn",
      "public_alb_security_group_id",
      "private_alb_http_listener_arn",
      "private_alb_https_listener_arn",
      "private_alb_security_group_id",
    ]) {
      assert.ok(clusterMappedInputIds.includes(inputId), `expected ECS cluster mapping ${inputId}`);
    }

    const clusterAlbVisibility = findInput(inputs, "ecs_cluster_alb_visibility");
    assert.equal(clusterAlbVisibility.default, "public");
    assert.equal(clusterAlbVisibility.immutable, undefined);
    assert.deepEqual(getValueOptions(clusterAlbVisibility), ["public", "private"]);
    assert.deepEqual(clusterAlbVisibility.show_when, {
      web_service_enabled: true,
      load_balancer_source: "ecs_cluster",
    });

    const loadBalancerAttachment = assertRecord(
      getEcsTerraformVariable(compiled.module, "load_balancer_attachment"),
      "load_balancer_attachment",
    );
    const listenerRules = loadBalancerAttachment.listener_rules;
    assert.ok(Array.isArray(listenerRules) && listenerRules.length === 1, "load balancer attachment should have one listener rule");
    const listenerArn = assertString(assertRecord(listenerRules[0], "listener rule").listener_arn);
    assert.match(listenerArn, /load_balancer_source == "standalone_alb"/);
    assert.match(listenerArn, /alb_https_listener_arn \|\| module\.input\.alb_http_listener_arn/);
    assert.match(listenerArn, /ecs_cluster_alb_visibility == "public"/);
    assert.match(listenerArn, /public_alb_https_listener_arn \|\| module\.input\.public_alb_http_listener_arn/);
    assert.match(listenerArn, /private_alb_https_listener_arn \|\| module\.input\.private_alb_http_listener_arn/);

    const loadBalancerSecurityGroupId = assertString(
      getEcsTerraformVariable(compiled.module, "load_balancer_security_group_id"),
    );
    assert.match(loadBalancerSecurityGroupId, /load_balancer_source == "standalone_alb"/);
    assert.match(loadBalancerSecurityGroupId, /alb_security_group_id/);
    assert.match(loadBalancerSecurityGroupId, /public_alb_security_group_id/);
    assert.match(loadBalancerSecurityGroupId, /private_alb_security_group_id/);
  });

  it("propagates shared build input guidance to every consumer", async () => {
    const definitionPaths = [
      ["compute", "ec2_service", "rvn-ec2-service-definition.yml"],
      ["compute", "ecs_service", "rvn-ecs-nlb-definition.yml"],
      ["compute", "ecs_service", "rvn-ecs-web-definition.yml"],
      ["compute", "ecs_service", "rvn-ecs-worker-definition.yml"],
      ["compute", "lambda", "rvn-lambda-definition.yml"],
      ["hosting", "static_site", "rvn-aws-static-definition.yml"],
    ];
    const definitions = await Promise.all(definitionPaths.map((path) => compileDefinitionFile(join(repoRoot, ...path))));

    for (const definition of definitions) {
      const inputs = getModuleInputs(definition.module);
      assert.equal(
        findInput(inputs, "source_repo").description,
        "Repository containing the application source for Dockerfile or Railpack builds.",
        `${definition.type} should include shared Git source guidance`,
      );

      const builderType = findInput(inputs, "build_infrastructure_type");
      assert.equal(
        builderType.description,
        "Use on-demand EC2 for predictable availability or EC2 Spot for lower cost with possible capacity delays or interruption.",
        `${definition.type} should include shared builder guidance`,
      );
      const builderOptions = builderType.values;
      assert.ok(Array.isArray(builderOptions), `${definition.type} builder type should have values`);
      assert.deepEqual(
        builderOptions.map((option) => {
          const value = assertRecord(option, `${definition.type} builder option`);
          return [value.value, value.description];
        }),
        [
          ["ec2", "Use on-demand capacity for predictable availability without Spot interruption."],
          ["ec2-spot", "Use lower-cost Spot capacity that can wait for capacity or be interrupted by AWS."],
        ],
      );
    }

    for (const definition of definitions.filter((candidate) => candidate.type !== "rvn-lambda")) {
      const inputs = getModuleInputs(definition.module);
      assert.equal(
        findInput(inputs, "railpack_install_cmd").description,
        "Optional dependency installation command. Leave blank to use Railpack detection.",
      );
      assert.equal(
        findInput(inputs, "railpack_build_cmd").description,
        "Optional application build command. Leave blank to use Railpack detection.",
      );
    }
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

function getDeployInputs(module: Record<string, unknown>): Record<string, unknown>[] {
  const deploy = assertRecord(module.deploy, "module.deploy");
  const inputs = deploy.inputs;
  assert.ok(Array.isArray(inputs), "module.deploy.inputs should be an array");
  return inputs.map((input) => assertRecord(input, "deploy input"));
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

function getBuildSourceShowWhen(input: Record<string, unknown>): unknown {
  const showWhen = assertRecord(input.show_when, `${String(input.id)}.show_when`);
  return showWhen.build_source;
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
