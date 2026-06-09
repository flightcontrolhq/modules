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
  diff?: string;
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

export interface RavionApiClientOptions {
  baseUrl?: string;
  token?: string;
  requireToken?: boolean;
}

const DEFAULT_RAVION_API_URL = "https://api.ravion.com";

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
      items.push(
        createItem(
          definition,
          "create-definition",
          dryRun,
          `Create module definition ${definition.type}.`,
          createDiff(undefined, { type: definition.type, name: definition.name, description: definition.description }),
        ),
      );
      if (!dryRun) {
        remoteDefinition = await client.createModuleDefinition({ type: definition.type, name: definition.name, description: definition.description });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
        inventory.versionsByDefinitionId[remoteDefinition.id] = [];
      }
    } else if (remoteDefinition.name !== definition.name || remoteDefinition.description !== definition.description) {
      items.push(
        createItem(
          definition,
          "patch-definition",
          dryRun,
          `Patch metadata for module definition ${definition.type}.`,
          createDiff(
            { type: remoteDefinition.type, name: remoteDefinition.name, description: remoteDefinition.description },
            { type: definition.type, name: definition.name, description: definition.description },
          ),
        ),
      );
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

    const latestRemoteVersion = remoteDefinition ? selectLatestVersion(inventory.versionsByDefinitionId[remoteDefinition.id] ?? []) : undefined;
    items.push(
      createItem(
        definition,
        "create-version",
        dryRun,
        `Create module version ${definition.type}@${definition.version}.`,
        createDiff(latestRemoteVersion?.config, definition.module),
      ),
    );
    if (!dryRun) {
      if (!remoteDefinition) {
        throw new PublishError(`Cannot create ${definition.type}@${definition.version}; module definition was not created.`);
      }
      await createVersionOrConfirmDuplicate(client, remoteDefinition.id, definition);
    }
  }

  return { dryRun, items };
}

export async function createDefaultRavionApiClient(options: RavionApiClientOptions = {}): Promise<RavionModuleApiClient> {
  const baseUrl = options.baseUrl ?? DEFAULT_RAVION_API_URL;
  const token = options.token ?? process.env.RAVION_API_TOKEN;
  if ((options.requireToken ?? true) && !token) {
    throw new PublishError("RAVION_API_TOKEN must be set to read or publish module definitions through the Ravion API.");
  }
  return new HttpRavionModuleApiClient(baseUrl, token);
}

export function formatPublishPlanMarkdown(result: PublishResult): string {
  const plannedChanges = result.items.filter((item) => item.action !== "skip-version");
  const lines = [
    "<!-- ravion-module-publish-plan -->",
    "## Ravion Module Publish Plan",
    "",
    result.dryRun ? "Dry run only. No Ravion API mutations were made." : "Applied publish changes to the Ravion API.",
    "",
  ];

  if (result.items.length === 0) {
    lines.push("No module definitions were found.", "");
    return lines.join("\n");
  }

  if (plannedChanges.length === 0) {
    lines.push("No publish changes are required. All local versions already exist remotely with identical config.", "");
  }

  lines.push("| Module | Version | Action | Summary |", "| --- | --- | --- | --- |");
  for (const item of result.items) {
    lines.push(`| \`${escapeMarkdownTableCell(item.type)}\` | \`${escapeMarkdownTableCell(item.version)}\` | ${formatAction(item.action)} | ${escapeMarkdownTableCell(item.message)} |`);
  }

  const itemsWithDiffs = plannedChanges.filter((item) => item.diff);
  if (itemsWithDiffs.length > 0) {
    lines.push("", "### Diffs", "");
    for (const item of itemsWithDiffs) {
      lines.push(`<details><summary>${escapeHtml(item.type)}@${escapeHtml(item.version)} ${escapeHtml(formatAction(item.action))}</summary>`, "", "```diff", truncateDiff(item.diff ?? ""), "```", "", "</details>", "");
    }
  }

  return lines.join("\n");
}

export async function loadRemoteInventory(client: RavionModuleApiClient): Promise<RemoteModuleInventory> {
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

function createItem(definition: CompiledDefinition, action: PublishAction, dryRun: boolean, message: string, diff?: string): PublishPlanItem {
  return { type: definition.type, version: definition.version, action, dryRun, message, diff };
}

function createDiff(remote: unknown, local: unknown): string | undefined {
  const remoteText = remote === undefined ? "" : stableStringifyPretty(remote);
  const localText = stableStringifyPretty(local);
  if (remoteText === localText) {
    return undefined;
  }

  return ["--- remote", "+++ local", ...remoteText.split("\n").filter(Boolean).map((line) => `-${line}`), ...localText.split("\n").filter(Boolean).map((line) => `+${line}`)].join("\n");
}

function stableStringifyPretty(value: unknown): string {
  return JSON.stringify(sortObjectKeys(value), null, 2);
}

function selectLatestVersion(versions: RemoteModuleVersion[]): RemoteModuleVersion | undefined {
  return [...versions].sort((left, right) => compareSemver(right.version, left.version))[0];
}

function compareSemver(left: string, right: string): number {
  const leftParts = left.split(".").map((part) => Number.parseInt(part, 10));
  const rightParts = right.split(".").map((part) => Number.parseInt(part, 10));
  for (let index = 0; index < 3; index += 1) {
    const difference = (leftParts[index] ?? 0) - (rightParts[index] ?? 0);
    if (difference !== 0) {
      return difference;
    }
  }
  return left.localeCompare(right);
}

function formatAction(action: PublishAction): string {
  return action
    .split("-")
    .map((part) => part[0].toUpperCase() + part.slice(1))
    .join(" ");
}

function escapeMarkdownTableCell(value: string): string {
  return value.replace(/\|/g, "\\|").replace(/\n/g, "<br>");
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;");
}

function truncateDiff(diff: string): string {
  const maxLength = 12000;
  if (diff.length <= maxLength) {
    return diff;
  }
  return `${diff.slice(0, maxLength)}\n... diff truncated ...`;
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
