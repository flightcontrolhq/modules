import { type CompiledDefinition } from "./compiler.js";
import { type RemoteModuleDefinition, type RemoteModuleInventory, type RemoteModuleVersion } from "./generate-definitions.js";
import { getReleaseStatuses, type ReleaseStatus, validateReleaseStatuses } from "./release.js";
import YAML from "yaml";

export type PublishAction = "create-definition" | "patch-definition" | "create-version" | "skip-version";

export interface PublishPlanItem {
  type: string;
  version: string;
  action: PublishAction;
  dryRun: boolean;
  message: string;
  description: string;
  diff?: string;
}

export interface PublishResult {
  dryRun: boolean;
  items: PublishPlanItem[];
  errors?: PublishPlanErrorItem[];
}

export interface PublishPlanErrorItem {
  type: string;
  version: string;
  message: string;
  latestVersion?: string;
  diff?: string;
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

export interface PublishOptions {
  dryRun?: boolean;
  logger?: (message: string) => void;
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

export class PublishPlanError extends Error {
  constructor(
    message: string,
    readonly result: PublishResult,
  ) {
    super(message);
    this.name = "PublishPlanError";
  }
}

export async function publishDefinitions(
  compiledDefinitions: CompiledDefinition[],
  client: RavionModuleApiClient,
  options: PublishOptions = {},
): Promise<PublishResult> {
  const dryRun = options.dryRun ?? true;
  const inventory = await loadRemoteInventory(client, { logger: options.logger });
  options.logger?.(`Loaded ${inventory.definitions.length} remote module definitions.`);
  const statuses = getReleaseStatuses(compiledDefinitions, { inventory });
  const errors = createPublishPlanErrors(statuses, compiledDefinitions, inventory);
  if (errors.length > 0) {
    throw new PublishPlanError("Release metadata validation failed.", { dryRun, items: [], errors });
  }
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
          definition.description,
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
          definition.description,
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
      items.push(createItem(definition, "skip-version", dryRun, `Skip ${definition.type}@${definition.version}; identical version already exists.`, remoteVersion.description));
      continue;
    }

    const latestRemoteVersion = remoteDefinition ? selectLatestVersion(inventory.versionsByDefinitionId[remoteDefinition.id] ?? []) : undefined;
    items.push(
      createItem(
        definition,
        "create-version",
        dryRun,
        `Create module version ${definition.type}@${definition.version}.`,
        definition.releaseDescription,
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

  if (result.errors && result.errors.length > 0) {
    lines.push("### 🚨 Release Config Conflicts 🚨", "", "These module versions already exist remotely with different compiled config. Publish a new version, or make the local definition match the existing remote version.", "");
    lines.push("| Module | Release Version | Latest Remote Version | Problem |", "| --- | --- | --- | --- |");
    for (const error of result.errors) {
      lines.push(`| \`${escapeMarkdownTableCell(error.type)}\` | \`${escapeMarkdownTableCell(error.version)}\` | ${error.latestVersion ? `\`${escapeMarkdownTableCell(error.latestVersion)}\`` : "n/a"} | ${escapeMarkdownTableCell(error.message)} |`);
    }

    const errorsWithDiffs = result.errors.filter((error) => error.diff);
    if (errorsWithDiffs.length > 0) {
      lines.push("", "### Latest Remote vs Compiled", "");
      for (const error of errorsWithDiffs) {
        lines.push(
          `<details><summary>${escapeHtml(error.type)} ${escapeHtml(error.latestVersion ?? "no remote version")} -> ${escapeHtml(error.version)}</summary>`,
          "",
          "```diff",
          truncateDiff(error.diff ?? ""),
          "```",
          "",
          "</details>",
          "",
        );
      }
    }

    return lines.join("\n");
  }

  if (result.items.length === 0) {
    lines.push("No module definitions were found.", "");
    return lines.join("\n");
  }

  if (plannedChanges.length === 0) {
    lines.push("No publish changes are required. All local versions already exist remotely with identical config.", "");
    return lines.join("\n");
  }

  lines.push("| Module | Version | Action | Summary |", "| --- | --- | --- | --- |");
  const byModule = (left: PublishPlanItem, right: PublishPlanItem) => left.type.localeCompare(right.type) || left.version.localeCompare(right.version);
  const skippedItems = result.items.filter((item) => item.action === "skip-version");
  for (const item of [...summarizePublishPlanTableItems(plannedChanges).sort(byModule), ...[...skippedItems].sort(byModule)]) {
    lines.push(`| \`${escapeMarkdownTableCell(item.type)}\` | \`${escapeMarkdownTableCell(item.version)}\` | ${formatAction(item.action)} | ${escapeMarkdownTableCell(item.description || item.message)} |`);
  }

  const itemsWithDiffs = plannedChanges.filter((item) => item.diff);
  if (itemsWithDiffs.length > 0) {
    lines.push("", "### Diffs", "");
    for (const item of itemsWithDiffs) {
      lines.push(`<details><summary>${escapeHtml(item.type)}@${escapeHtml(item.version)}</summary>`, "", "```diff", truncateDiff(item.diff ?? ""), "```", "", "</details>", "");
    }
  }

  return lines.join("\n");
}

export function isPublishPlanError(error: unknown): error is PublishPlanError {
  return error instanceof PublishPlanError;
}

export async function loadRemoteInventory(client: RavionModuleApiClient, options: { logger?: (message: string) => void } = {}): Promise<RemoteModuleInventory> {
  options.logger?.("Loading remote module definitions from Ravion API.");
  const definitions = await wrapApiStep("list remote module definitions", () => client.listModuleDefinitions());
  options.logger?.(`Loading remote module versions for ${definitions.length} definitions.`);
  const versions = await Promise.all(
    definitions.map(async (definition) => {
      const label = `${definition.type} (${definition.id})`;
      return [definition.id, await wrapApiStep(`list remote module versions for ${label}`, () => client.listModuleVersions(definition.id))] as const;
    }),
  );
  return { definitions, versionsByDefinitionId: Object.fromEntries(versions) };
}

async function wrapApiStep<T>(label: string, run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (error) {
    throw new PublishError(`Failed to ${label}: ${formatUnknownError(error)}`);
  }
}

function createPublishPlanErrors(statuses: ReleaseStatus[], compiledDefinitions: CompiledDefinition[], inventory: RemoteModuleInventory): PublishPlanErrorItem[] {
  const compiledByType = new Map(compiledDefinitions.map((definition) => [definition.type, definition]));
  return statuses
    .filter((status) => status.publishState === "conflict" || (status.publishState === "unpublished" && status.releaseDescription.trim().length === 0))
    .map((status) => {
      const compiled = compiledByType.get(status.type);
      const remoteVersions = status.remoteDefinitionId ? (inventory.versionsByDefinitionId[status.remoteDefinitionId] ?? []) : [];
      const latestVersion = selectLatestVersion(remoteVersions);
      return {
        type: status.type,
        version: status.version,
        message: status.message,
        latestVersion: latestVersion?.version,
        diff: compiled ? createDiff(latestVersion?.config, compiled.module) : undefined,
      };
    });
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

function createItem(definition: CompiledDefinition, action: PublishAction, dryRun: boolean, message: string, description: string, diff?: string): PublishPlanItem {
  return { type: definition.type, version: definition.version, action, dryRun, message, description, diff };
}

function summarizePublishPlanTableItems(items: PublishPlanItem[]): PublishPlanItem[] {
  const rows: PublishPlanItem[] = [];
  for (const item of items) {
    const existingIndex = rows.findIndex((row) => row.type === item.type && row.version === item.version);
    if (existingIndex === -1) {
      rows.push(item);
    } else if (rows[existingIndex].action !== "create-version" && item.action === "create-version") {
      rows[existingIndex] = item;
    }
  }
  return rows;
}

function createDiff(remote: unknown, local: unknown): string | undefined {
  const remoteText = remote === undefined ? "" : stableStringifyYaml(remote);
  const localText = stableStringifyYaml(local);
  if (remoteText === localText) {
    return undefined;
  }

  return createUnifiedDiff(remoteText, localText);
}

function createUnifiedDiff(remoteText: string, localText: string, contextLineCount = 3): string {
  const remoteLines = remoteText.split("\n");
  const localLines = localText.split("\n");
  const operations = diffLines(remoteLines, localLines);
  const changedIndexes = operations.flatMap((operation, index) => (operation.type === "equal" ? [] : [index]));
  if (changedIndexes.length === 0) {
    return "";
  }

  const selected = new Set<number>();
  for (const index of changedIndexes) {
    for (let selectedIndex = Math.max(0, index - contextLineCount); selectedIndex <= Math.min(operations.length - 1, index + contextLineCount); selectedIndex += 1) {
      selected.add(selectedIndex);
    }
  }

  const lines = ["--- remote", "+++ compiled"];
  let previousIndex = -1;
  for (const index of [...selected].sort((left, right) => left - right)) {
    if (previousIndex >= 0 && index > previousIndex + 1) {
      lines.push("@@");
    }
    const operation = operations[index];
    lines.push(`${operation.type === "add" ? "+" : operation.type === "remove" ? "-" : " "}${operation.line}`);
    previousIndex = index;
  }

  return lines.join("\n");
}

function diffLines(remoteLines: string[], localLines: string[]): Array<{ type: "equal" | "remove" | "add"; line: string }> {
  const lengths = Array.from({ length: remoteLines.length + 1 }, () => Array<number>(localLines.length + 1).fill(0));
  for (let remoteIndex = remoteLines.length - 1; remoteIndex >= 0; remoteIndex -= 1) {
    for (let localIndex = localLines.length - 1; localIndex >= 0; localIndex -= 1) {
      lengths[remoteIndex][localIndex] = remoteLines[remoteIndex] === localLines[localIndex]
        ? lengths[remoteIndex + 1][localIndex + 1] + 1
        : Math.max(lengths[remoteIndex + 1][localIndex], lengths[remoteIndex][localIndex + 1]);
    }
  }

  const operations: Array<{ type: "equal" | "remove" | "add"; line: string }> = [];
  let remoteIndex = 0;
  let localIndex = 0;
  while (remoteIndex < remoteLines.length && localIndex < localLines.length) {
    if (remoteLines[remoteIndex] === localLines[localIndex]) {
      operations.push({ type: "equal", line: remoteLines[remoteIndex] });
      remoteIndex += 1;
      localIndex += 1;
    } else if (lengths[remoteIndex + 1][localIndex] >= lengths[remoteIndex][localIndex + 1]) {
      operations.push({ type: "remove", line: remoteLines[remoteIndex] });
      remoteIndex += 1;
    } else {
      operations.push({ type: "add", line: localLines[localIndex] });
      localIndex += 1;
    }
  }
  while (remoteIndex < remoteLines.length) {
    operations.push({ type: "remove", line: remoteLines[remoteIndex] });
    remoteIndex += 1;
  }
  while (localIndex < localLines.length) {
    operations.push({ type: "add", line: localLines[localIndex] });
    localIndex += 1;
  }

  return operations;
}

function stableStringifyYaml(value: unknown): string {
  return YAML.stringify(sortObjectKeys(value), { lineWidth: 0 }).trimEnd();
}

function selectLatestVersion(versions: RemoteModuleVersion[]): RemoteModuleVersion | undefined {
  return [...versions].sort((left, right) => compareSemver(right.version, left.version))[0];
}

function compareSemver(left: string, right: string): number {
  const leftParsed = parseSemver(left);
  const rightParsed = parseSemver(right);
  for (let index = 0; index < 3; index += 1) {
    const difference = leftParsed.numbers[index] - rightParsed.numbers[index];
    if (difference !== 0) {
      return difference;
    }
  }

  if (leftParsed.prerelease && !rightParsed.prerelease) {
    return -1;
  }
  if (!leftParsed.prerelease && rightParsed.prerelease) {
    return 1;
  }
  return left.localeCompare(right);
}

function parseSemver(version: string): { numbers: [number, number, number]; prerelease?: string } {
  const [core, prerelease] = version.split("-", 2);
  const parts = core.split(".").map((part) => Number.parseInt(part, 10));
  return { numbers: [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0], prerelease };
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
    return this.list<RemoteModuleDefinition>("/module-definitions");
  }

  async createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition> {
    return this.call<RemoteModuleDefinition>("POST", "/module-definitions", { data: input });
  }

  async patchModuleDefinition(input: RemoteModuleDefinition): Promise<RemoteModuleDefinition> {
    return this.call<RemoteModuleDefinition>("PATCH", `/module-definitions/${encodeURIComponent(input.id)}`, { data: { name: input.name, description: input.description } });
  }

  async listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]> {
    return this.list<RemoteModuleVersion>("/module-versions", { moduleDefinitionId });
  }

  async createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion> {
    return this.call<RemoteModuleVersion>("POST", "/module-versions", { data: input });
  }

  private async list<T>(path: string, query: Record<string, string> = {}): Promise<T[]> {
    const items: T[] = [];
    let cursor: string | undefined;

    do {
      const response = await this.call<{ data: T[]; meta?: { nextCursor?: string } }>("GET", path, undefined, { ...query, limit: "100", ...(cursor ? { cursor } : {}) }, { unwrap: false });
      items.push(...response.data);
      cursor = response.meta?.nextCursor;
    } while (cursor);

    return items;
  }

  private async call<T>(method: string, path: string, input?: unknown, query: Record<string, string> = {}, options: { unwrap?: boolean } = {}): Promise<T> {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.token) {
      headers.Authorization = `Bearer ${this.token}`;
    }

    const url = buildUrl(this.baseUrl, path, query);
    let response: Response;
    try {
      response = await fetch(url, { method, headers, body: input === undefined ? undefined : JSON.stringify(input) });
    } catch (error) {
      throw new PublishError(`Ravion API request failed before receiving a response: ${method} ${url}: ${formatUnknownError(error)}`);
    }
    const payload = await readResponsePayload(response);
    if (!response.ok) {
      const message = extractErrorMessage(payload, "No response error message was returned.");
      throw new HttpApiError(response.status, `${method} ${url} failed with HTTP ${response.status}: ${message}\nResponse body:\n${formatResponsePayload(payload)}`);
    }
    return (options.unwrap === false ? payload : unwrapApiPayload(payload)) as T;
  }
}

function buildUrl(baseUrl: string, path: string, query: Record<string, string>): string {
  const url = new URL(`${baseUrl}${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }
  return url.toString();
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
    const parts = [];
    if (typeof payload.code === "string") {
      parts.push(`code=${payload.code}`);
    }
    if (typeof payload.message === "string") {
      parts.push(payload.message);
    }
    if (typeof payload.description === "string") {
      parts.push(payload.description);
    }
    if (typeof payload.requestId === "string") {
      parts.push(`requestId=${payload.requestId}`);
    }
    if (parts.length > 0) {
      return parts.join("; ");
    }
    if (isRecord(payload.error)) {
      return extractErrorMessage(payload.error, fallback);
    }
  }
  return typeof payload === "string" && payload.length > 0 ? payload : fallback;
}

function formatResponsePayload(payload: unknown): string {
  if (typeof payload === "string") {
    return payload;
  }
  return JSON.stringify(payload, null, 2);
}

function formatUnknownError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return String(error);
}
