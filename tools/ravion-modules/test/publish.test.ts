import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { type CompiledDefinition } from "../src/compiler.js";
import { type RemoteModuleDefinition, type RemoteModuleVersion } from "../src/generate-definitions.js";
import { publishDefinitions, PublishError, type ModuleDefinitionInput, type ModuleVersionInput, type RavionModuleApiClient } from "../src/publish.js";
import { ReleaseMetadataError } from "../src/release.js";

describe("publish", () => {
  it("creates missing definitions and versions through the Ravion API", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action, dryRun }) => ({ action, dryRun })), [
      { action: "create-definition", dryRun: false },
      { action: "create-version", dryRun: false },
    ]);
    assert.deepEqual(client.createdDefinitions, [{ type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }]);
    assert.deepEqual(client.createdVersions.map(({ moduleDefinitionId, version, description, config }) => ({ moduleDefinitionId, version, description, config })), [
      { moduleDefinitionId: "definition-1", version: "1.2.3", description: "Add subnet options.", config: { inputs: [{ id: "name", type: "string", label: "Name" }] } },
    ]);
  });

  it("patches metadata changes before publishing versions", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "Old name", description: "Old description" }] });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["patch-definition", "create-version"]);
    assert.deepEqual(client.patchedDefinitions, [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }]);
  });

  it("skips identical existing versions idempotently", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: createCompiledDefinition().module })] },
    });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["skip-version"]);
    assert.equal(client.createdVersions.length, 0);
  });

  it("fails when an existing version has different config", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: { inputs: [{ id: "region", type: "string", label: "Region" }] } })] },
    });

    await assert.rejects(() => publishDefinitions([createCompiledDefinition()], client), (error) => error instanceof ReleaseMetadataError);
  });

  it("sends release.description as ModuleVersion.description", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });

    await publishDefinitions([createCompiledDefinition({ releaseDescription: "Curated changelog entry." })], client, { dryRun: false });

    assert.equal(client.createdVersions[0].description, "Curated changelog entry.");
  });

  it("does not mutate the API in dry-run mode", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client);

    assert.equal(result.dryRun, true);
    assert.deepEqual(result.items.map(({ action }) => action), ["create-definition", "create-version"]);
    assert.equal(client.createdDefinitions.length, 0);
    assert.equal(client.createdVersions.length, 0);
  });

  it("handles duplicate version responses as an idempotent skip when the remote config matches", async () => {
    const compiled = createCompiledDefinition();
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });
    client.onCreateVersion = async (input) => {
      client.versionsByDefinitionId[input.moduleDefinitionId] = [createRemoteVersion({ config: compiled.module })];
      throw new Error("Duplicate version already exists");
    };

    const result = await publishDefinitions([compiled], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["create-version"]);
  });

  it("fails duplicate version responses when the remote config differs", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });
    client.onCreateVersion = async (input) => {
      client.versionsByDefinitionId[input.moduleDefinitionId] = [createRemoteVersion({ config: { inputs: [{ id: "region", type: "string", label: "Region" }] } })];
      throw new Error("Duplicate version already exists");
    };

    await assert.rejects(() => publishDefinitions([createCompiledDefinition()], client, { dryRun: false }), (error) => error instanceof PublishError);
  });
});

function createCompiledDefinition(overrides: Partial<CompiledDefinition> = {}): CompiledDefinition {
  return {
    filePath: join("/repo", "networking", "vpc", "definition.yml"),
    type: "ravion-aws-vpc",
    name: "AWS VPC",
    description: "AWS VPC and subnets.",
    version: "1.2.3",
    releaseDescription: "Add subnet options.",
    module: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    ...overrides,
  };
}

function createRemoteVersion(overrides: Partial<RemoteModuleVersion> = {}): RemoteModuleVersion {
  return {
    moduleDefinitionId: "vpc",
    version: "1.2.3",
    description: "Add subnet options.",
    config: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    ...overrides,
  };
}

class MockRavionClient implements RavionModuleApiClient {
  definitions: RemoteModuleDefinition[];
  versionsByDefinitionId: Record<string, RemoteModuleVersion[]>;
  createdDefinitions: ModuleDefinitionInput[] = [];
  patchedDefinitions: RemoteModuleDefinition[] = [];
  createdVersions: ModuleVersionInput[] = [];
  onCreateVersion?: (input: ModuleVersionInput) => Promise<void>;

  constructor(options: { definitions?: RemoteModuleDefinition[]; versionsByDefinitionId?: Record<string, RemoteModuleVersion[]> } = {}) {
    this.definitions = options.definitions ?? [];
    this.versionsByDefinitionId = options.versionsByDefinitionId ?? {};
  }

  async listModuleDefinitions(): Promise<RemoteModuleDefinition[]> {
    return this.definitions;
  }

  async createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition> {
    this.createdDefinitions.push(input);
    const definition = { id: `definition-${this.definitions.length + 1}`, ...input };
    this.definitions.push(definition);
    return definition;
  }

  async patchModuleDefinition(input: RemoteModuleDefinition): Promise<RemoteModuleDefinition> {
    this.patchedDefinitions.push(input);
    this.definitions = this.definitions.map((definition) => (definition.id === input.id ? input : definition));
    return input;
  }

  async listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]> {
    return this.versionsByDefinitionId[moduleDefinitionId] ?? [];
  }

  async createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion> {
    if (this.onCreateVersion) {
      await this.onCreateVersion(input);
    }
    this.createdVersions.push(input);
    const version = { ...input };
    this.versionsByDefinitionId[input.moduleDefinitionId] = [...(this.versionsByDefinitionId[input.moduleDefinitionId] ?? []), version];
    return version;
  }
}
