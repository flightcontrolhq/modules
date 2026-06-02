import { type CompiledDefinition } from "./compiler.js";
import { type RemoteModuleDefinition, type RemoteModuleInventory, type RemoteModuleVersion } from "./generate-definitions.js";
import { getReleaseStatuses, validateReleaseStatuses } from "./release.js";

export type PublishAction = "create-definition" | "patch-definition" | "create-version" | "skip-version";

export interface PublishPlanItem {
  type: string;
  version: string;
  action: PublishAction;
  dryRun: boolean;
  message: string;
}

export interface PublishResult {
  dryRun: boolean;
  items: PublishPlanItem[];
}

export interface ModuleDefinitionInput {
  type: string;
  name: string;
  description: string;
}

export interface ModuleVersionInput {
  moduleDefinitionId: string;
  version: string;
  description: string;
  config: Record<string, unknown>;
}

export interface RavionModuleApiClient {
  listModuleDefinitions(): Promise<RemoteModuleDefinition[]>;
  createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition>;
  patchModuleDefinition(input: RemoteModuleDefinition): Promise<RemoteModuleDefinition>;
  listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]>;
  createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion>;
}

export class PublishError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PublishError";
  }
}

export async function publishDefinitions(
  compiledDefinitions: CompiledDefinition[],
  client: RavionModuleApiClient,
  options: { dryRun?: boolean } = {},
): Promise<PublishResult> {
  const dryRun = options.dryRun ?? true;
  const inventory = await loadRemoteInventory(client);
  const statuses = getReleaseStatuses(compiledDefinitions, { inventory });
  validateReleaseStatuses(statuses);

  const definitionsByType = new Map(inventory.definitions.map((definition) => [definition.type, definition]));
  const items: PublishPlanItem[] = [];

  for (const definition of [...compiledDefinitions].sort((left, right) => left.type.localeCompare(right.type))) {
    let remoteDefinition = definitionsByType.get(definition.type);
    if (!remoteDefinition) {
      items.push(createItem(definition, "create-definition", dryRun, `Create module definition ${definition.type}.`));
      if (!dryRun) {
        remoteDefinition = await client.createModuleDefinition({ type: definition.type, name: definition.name, description: definition.description });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
        inventory.versionsByDefinitionId[remoteDefinition.id] = [];
      }
    } else if (remoteDefinition.name !== definition.name || remoteDefinition.description !== definition.description) {
      items.push(createItem(definition, "patch-definition", dryRun, `Patch metadata for module definition ${definition.type}.`));
      if (!dryRun) {
        remoteDefinition = await client.patchModuleDefinition({ ...remoteDefinition, name: definition.name, description: definition.description });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
      }
    }

    const remoteVersion = remoteDefinition ? (inventory.versionsByDefinitionId[remoteDefinition.id] ?? []).find((version) => version.version === definition.version) : undefined;
    if (remoteVersion) {
      items.push(createItem(definition, "skip-version", dryRun, `Skip ${definition.type}@${definition.version}; identical version already exists.`));
      continue;
    }

    items.push(createItem(definition, "create-version", dryRun, `Create module version ${definition.type}@${definition.version}.`));
    if (!dryRun) {
      if (!remoteDefinition) {
        throw new PublishError(`Cannot create ${definition.type}@${definition.version}; module definition was not created.`);
      }
      await createVersionOrConfirmDuplicate(client, remoteDefinition.id, definition);
    }
  }

  return { dryRun, items };
}

export async function createDefaultRavionApiClient(options: { baseUrl?: string; token?: string } = {}): Promise<RavionModuleApiClient> {
  const baseUrl = options.baseUrl ?? process.env.RAVION_API_URL;
  if (!baseUrl) {
    throw new PublishError("RAVION_API_URL must be set to publish through the Ravion API.");
  }
  const token = options.token ?? process.env.RAVION_API_TOKEN;
  return new HttpRavionModuleApiClient(baseUrl, token);
}

async function loadRemoteInventory(client: RavionModuleApiClient): Promise<RemoteModuleInventory> {
  const definitions = await client.listModuleDefinitions();
  const versions = await Promise.all(definitions.map(async (definition) => [definition.id, await client.listModuleVersions(definition.id)] as const));
  return { definitions, versionsByDefinitionId: Object.fromEntries(versions) };
}

async function createVersionOrConfirmDuplicate(client: RavionModuleApiClient, moduleDefinitionId: string, definition: CompiledDefinition): Promise<void> {
  try {
    await client.createModuleVersion({
      moduleDefinitionId,
      version: definition.version,
      description: definition.releaseDescription,
      config: definition.module,
    });
  } catch (error) {
    if (!isDuplicateVersionError(error)) {
      throw error;
    }
    const duplicateVersion = (await client.listModuleVersions(moduleDefinitionId)).find((version) => version.version === definition.version);
    if (!duplicateVersion || stableStringify(duplicateVersion.config) !== stableStringify(definition.module)) {
      throw new PublishError(`${definition.type}@${definition.version} already exists remotely with different compiled config.`);
    }
  }
}

function createItem(definition: CompiledDefinition, action: PublishAction, dryRun: boolean, message: string): PublishPlanItem {
  return { type: definition.type, version: definition.version, action, dryRun, message };
}

function isDuplicateVersionError(error: unknown): boolean {
  if (error instanceof HttpApiError && error.status === 409) {
    return true;
  }
  return error instanceof Error && /duplicate|already exists|conflict/i.test(error.message);
}

function stableStringify(value: unknown): string {
  return JSON.stringify(sortObjectKeys(value));
}

function sortObjectKeys(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => sortObjectKeys(item));
  }
  if (!isRecord(value)) {
    return value;
  }
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortObjectKeys(value[key])]));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

class HttpApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "HttpApiError";
  }
}

class HttpRavionModuleApiClient implements RavionModuleApiClient {
  private readonly baseUrl: string;

  constructor(baseUrl: string, private readonly token?: string) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
  }

  async listModuleDefinitions(): Promise<RemoteModuleDefinition[]> {
    return this.call<RemoteModuleDefinition[]>("moduleDefinitions.listModuleDefinitions", {});
  }

  async createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition> {
    return this.call<RemoteModuleDefinition>("moduleDefinitions.createModuleDefinition", input);
  }

  async patchModuleDefinition(input: RemoteModuleDefinition): Promise<RemoteModuleDefinition> {
    return this.call<RemoteModuleDefinition>("moduleDefinitions.patchModuleDefinition", input);
  }

  async listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]> {
    return this.call<RemoteModuleVersion[]>("moduleVersions.listModuleVersions", { moduleDefinitionId });
  }

  async createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion> {
    return this.call<RemoteModuleVersion>("moduleVersions.createModuleVersion", input);
  }

  private async call<T>(procedure: string, input: unknown): Promise<T> {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.token) {
      headers.Authorization = `Bearer ${this.token}`;
    }

    const response = await fetch(`${this.baseUrl}/${procedure}`, { method: "POST", headers, body: JSON.stringify(input) });
    const payload = await readResponsePayload(response);
    if (!response.ok) {
      throw new HttpApiError(response.status, extractErrorMessage(payload, `${procedure} failed with HTTP ${response.status}.`));
    }
    return unwrapApiPayload(payload) as T;
  }
}

async function readResponsePayload(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text.trim().length === 0) {
    return undefined;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function unwrapApiPayload(payload: unknown): unknown {
  if (!isRecord(payload)) {
    return payload;
  }
  if ("result" in payload) {
    const result = payload.result;
    return isRecord(result) && "data" in result ? result.data : result;
  }
  if ("data" in payload) {
    return payload.data;
  }
  return payload;
}

function extractErrorMessage(payload: unknown, fallback: string): string {
  if (isRecord(payload)) {
    if (typeof payload.message === "string") {
      return payload.message;
    }
    if (isRecord(payload.error) && typeof payload.error.message === "string") {
      return payload.error.message;
    }
  }
  return typeof payload === "string" && payload.length > 0 ? payload : fallback;
}
