import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { type CompiledDefinition } from "../src/compiler.js";
import { type RemoteModuleDefinition, type RemoteModuleVersion } from "../src/generate-definitions.js";
import {
  createDefaultRavionApiClient,
  formatPublishPlanMarkdown,
  publishDefinitions,
  PublishError,
  type ModuleDefinitionInput,
  type ModuleVersionInput,
  type RavionModuleApiClient,
} from "../src/publish.js";
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

  it("formats a markdown dry-run plan with diffs", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client);
    const markdown = formatPublishPlanMarkdown(result);

    assert.match(markdown, /<!-- ravion-module-publish-plan -->/);
    assert.match(markdown, /Dry run only/);
    assert.match(markdown, /Create Definition/);
    assert.match(markdown, /Create Version/);
    assert.match(markdown, /```diff/);
    assert.match(markdown, /\+  "type": "ravion-aws-vpc"/);
  });

  it("requires a Ravion API token by default", async () => {
    await assert.rejects(() => createDefaultRavionApiClient({ token: "" }), {
      name: "PublishError",
      message: "RAVION_API_TOKEN must be set to read or publish module definitions through the Ravion API.",
    });
  });

  it("adds inventory context when loading remote versions fails", async () => {
    const logs: string[] = [];
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });
    client.onListModuleVersions = async () => {
      throw new Error("Forbidden");
    };

    await assert.rejects(() => publishDefinitions([createCompiledDefinition()], client, { logger: (message) => logs.push(message) }), {
      name: "PublishError",
      message: "Failed to list remote module versions for ravion-aws-vpc (vpc): Error: Forbidden",
    });
    assert.deepEqual(logs, ["Loading remote module definitions from Ravion API.", "Loading remote module versions for 1 definitions."]);
  });

  it("uses the OpenAPI REST endpoints and data envelopes", async () => {
    const calls: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), method: init?.method ?? "GET", body: init?.body ? JSON.parse(String(init.body)) : undefined });
      if (String(url).includes("/module-definitions?")) {
        return jsonResponse({ data: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }], meta: { limit: 100 } });
      }
      if (String(url).includes("/module-versions?")) {
        return jsonResponse({ data: [], meta: { limit: 100 } });
      }
      if (String(url).endsWith("/module-definitions")) {
        return jsonResponse({ data: { id: "created", type: "ravion-aws-new", name: "New", description: "New module." } }, 201);
      }
      if (String(url).endsWith("/module-definitions/vpc")) {
        return jsonResponse({ data: { id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "New description." } });
      }
      if (String(url).endsWith("/module-versions")) {
        return jsonResponse({ data: { id: "version", moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} } }, 201);
      }
      throw new Error(`Unexpected fetch URL ${url}`);
    };

    try {
      const client = await createDefaultRavionApiClient({ baseUrl: "https://api.example.test", token: "token" });
      await client.listModuleDefinitions();
      await client.listModuleVersions("vpc");
      await client.createModuleDefinition({ type: "ravion-aws-new", name: "New", description: "New module." });
      await client.patchModuleDefinition({ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "New description." });
      await client.createModuleVersion({ moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} });
    } finally {
      globalThis.fetch = originalFetch;
    }

    assert.deepEqual(calls, [
      { url: "https://api.example.test/module-definitions?limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-versions?moduleDefinitionId=vpc&limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-definitions", method: "POST", body: { data: { type: "ravion-aws-new", name: "New", description: "New module." } } },
      { url: "https://api.example.test/module-definitions/vpc", method: "PATCH", body: { data: { name: "AWS VPC", description: "New description." } } },
      {
        url: "https://api.example.test/module-versions",
        method: "POST",
        body: { data: { moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} } },
      },
    ]);
  });

  it("includes REST error response details", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => jsonResponse({ code: "Ravion:Auth:FORBIDDEN", message: "Forbidden", description: "Missing scope", requestId: "req_123" }, 403);

    try {
      const client = await createDefaultRavionApiClient({ baseUrl: "https://api.example.test", token: "token" });
      await assert.rejects(() => client.listModuleDefinitions(), {
        name: "HttpApiError",
        message:
          'GET https://api.example.test/module-definitions?limit=100 failed with HTTP 403: code=Ravion:Auth:FORBIDDEN; Forbidden; Missing scope; requestId=req_123\nResponse body:\n{\n  "code": "Ravion:Auth:FORBIDDEN",\n  "message": "Forbidden",\n  "description": "Missing scope",\n  "requestId": "req_123"\n}',
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
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

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

class MockRavionClient implements RavionModuleApiClient {
  definitions: RemoteModuleDefinition[];
  versionsByDefinitionId: Record<string, RemoteModuleVersion[]>;
  createdDefinitions: ModuleDefinitionInput[] = [];
  patchedDefinitions: RemoteModuleDefinition[] = [];
  createdVersions: ModuleVersionInput[] = [];
  onListModuleVersions?: (moduleDefinitionId: string) => Promise<RemoteModuleVersion[]>;
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
    if (this.onListModuleVersions) {
      return this.onListModuleVersions(moduleDefinitionId);
    }
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
