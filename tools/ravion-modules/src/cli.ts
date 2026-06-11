#!/usr/bin/env node
import { execFile } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { basename } from "node:path";
import { promisify } from "node:util";
import { parseAuthoringDefinitionFile } from "./authoring-schema.js";
import { compileAllDefinitions, compileDefinitionFile, findDefinitionFiles } from "./compiler.js";
import { generateDefinitionsFromInventory, readInventoryFile, validateGeneratedDefinitions } from "./generate-definitions.js";
import { createPlannedGitHubReleases, planGitHubReleases, readTagPlanFile } from "./github-releases.js";
import { runMigrationGuardrails } from "./guardrails.js";
import { validateModuleConfig } from "./module-schema.js";
import { createDefaultRavionApiClient, formatPublishPlanMarkdown, isPublishPlanError, loadRemoteInventory, publishDefinitions } from "./publish.js";
import { getReleaseStatuses, validateReleaseStatuses } from "./release.js";
import { createPlannedTags, getCurrentCommit, listExistingTags, planTags, pushPlannedTags } from "./tags.js";

const [, , command, ...args] = process.argv;
const execFileAsync = promisify(execFile);

await main().catch((error) => {
  console.error(formatError(error));
  process.exitCode = 1;
});

async function main(): Promise<void> {
if (command === "validate") {
  for (const filePath of args) {
    await parseAuthoringDefinitionFile(filePath);
    const compiled = await compileDefinitionFile(filePath);
    validateModuleConfig(compiled.module, compiled.filePath);
  }
} else if (command === "compile") {
  const compiled = args.length > 0 ? await Promise.all(args.map((filePath) => compileDefinitionFile(filePath))) : await compileAllDefinitions();
  validateReleaseStatuses(getReleaseStatuses(compiled));
  console.log(JSON.stringify(compiled, null, 2));
} else if (command === "guardrails") {
  await runMigrationGuardrails(getRootArg(args));
  console.log(JSON.stringify({ ok: true }, null, 2));
} else if (command === "status") {
  const inventoryIndex = args.indexOf("--inventory");
  const inventory = inventoryIndex >= 0 && args[inventoryIndex + 1] ? await readInventoryFile(args[inventoryIndex + 1]) : undefined;
  const compiled = await compileAllDefinitions();
  const statuses = getReleaseStatuses(compiled, { inventory });
  validateReleaseStatuses(statuses);
  console.log(JSON.stringify(statuses, null, 2));
} else if (command === "tags") {
  const inventoryIndex = args.indexOf("--inventory");
  const targetIndex = args.indexOf("--target");
  const inventory = args.includes("--api")
    ? await loadRemoteInventory(await createDefaultRavionApiClient())
    : inventoryIndex >= 0 && args[inventoryIndex + 1]
      ? await readInventoryFile(args[inventoryIndex + 1])
      : undefined;
  const targetCommit = targetIndex >= 0 && args[targetIndex + 1] ? args[targetIndex + 1] : await getCurrentCommit();
  const compiled = await compileAllDefinitions();
  const statuses = getReleaseStatuses(compiled, { inventory });
  validateReleaseStatuses(statuses);
  const plan = planTags(statuses, await listExistingTags(), targetCommit, { overwrite: args.includes("--overwrite") });
  if (args.includes("--create")) {
    await createPlannedTags(plan);
  }
  console.log(JSON.stringify(plan, null, 2));
} else if (command === "push-tags") {
  const planPath = getArgValue(args, "--plan");
  if (!planPath) {
    console.error("Usage: ravion-modules push-tags --plan <tag-plan.json>");
    process.exitCode = 1;
    return;
  }
  const plan = await readTagPlanFile(planPath);
  await pushPlannedTags(plan);
  console.log(JSON.stringify(plan, null, 2));
} else if (command === "github-releases") {
  const planPath = getArgValue(args, "--plan");
  if (!planPath) {
    console.error("Usage: ravion-modules github-releases --plan <tag-plan.json> [--create]");
    process.exitCode = 1;
    return;
  }
  const plan = await planGitHubReleases(await readTagPlanFile(planPath));
  if (args.includes("--create")) {
    await createPlannedGitHubReleases(plan);
  }
  console.log(JSON.stringify(plan, null, 2));
} else if (command === "publish") {
  const definitionFilePaths = getPositionalArgs(args, new Set(["--format", "--output"]));
  const resolvedDefinitionFilePaths = await resolveDefinitionFileArgs(definitionFilePaths);
  const compiled = resolvedDefinitionFilePaths.length > 0 ? await Promise.all(resolvedDefinitionFilePaths.map((filePath) => compileDefinitionFile(filePath))) : await compileAllDefinitions();
  for (const definition of compiled) {
    validateModuleConfig(definition.module, definition.filePath);
  }
  const localDev = args.includes("--local-dev");
  const client = await createDefaultRavionApiClient({ baseUrl: localDev ? (process.env.RAVION_API_URL ?? "http://localhost:8080") : undefined, requireToken: !localDev });
  const localDevSourceRef = localDev ? await resolveLocalDevSourceRef() : undefined;
  const format = getArgValue(args, "--format") ?? "json";
  const outputPath = getArgValue(args, "--output");
  let result;
  try {
    result = await publishDefinitions(compiled, client, { dryRun: localDev ? args.includes("--dry-run") : !args.includes("--apply"), localDev, localDevSourceRef, logger: (message) => console.error(`[publish] ${message}`) });
  } catch (error) {
    if (isPublishPlanError(error)) {
      const output = format === "markdown" ? formatPublishPlanMarkdown(error.result) : JSON.stringify(error.result, null, 2);
      if (outputPath) {
        await writeFile(outputPath, output);
      } else {
        console.log(output);
      }
    }
    throw error;
  }
  const output = format === "markdown" ? formatPublishPlanMarkdown(result) : JSON.stringify(result, null, 2);
  if (outputPath) {
    await writeFile(outputPath, output);
  } else {
    console.log(output);
  }
} else if (command === "generate-definitions") {
  const inventoryPath = args.find((arg) => !arg.startsWith("--"));
  if (!inventoryPath) {
    console.error("Usage: ravion-modules generate-definitions <inventory.json> [--write]");
    process.exitCode = 1;
  } else {
    const result = await generateDefinitionsFromInventory(await readInventoryFile(inventoryPath), process.cwd(), { write: args.includes("--write") });
    if (args.includes("--write")) {
      await validateGeneratedDefinitions(result);
    }
    console.log(JSON.stringify({ generated: result.generated.map(({ content: _content, ...item }) => item), missing: result.missing }, null, 2));
  }
} else {
  console.error("Usage: ravion-modules <validate|compile|guardrails|status|tags|push-tags|github-releases|publish|generate-definitions> <*-definition.yml...>");
  process.exitCode = 1;
}
}

function getRootArg(args: string[]): string | undefined {
  return getArgValue(args, "--root");
}

function getArgValue(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function getPositionalArgs(args: string[], flagsWithValues: Set<string>): string[] {
  const positional: string[] = [];
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (flagsWithValues.has(arg)) {
      index += 1;
    } else if (!arg.startsWith("--")) {
      positional.push(arg);
    }
  }
  return positional;
}

async function resolveDefinitionFileArgs(filePaths: string[]): Promise<string[]> {
  if (filePaths.length === 0) {
    return [];
  }

  const bareNames = filePaths.filter((filePath) => basename(filePath) === filePath);
  if (bareNames.length === 0) {
    return filePaths;
  }

  const definitionFiles = await findDefinitionFiles(process.cwd());
  return filePaths.map((filePath) => {
    if (basename(filePath) !== filePath) {
      return filePath;
    }

    const expectedFileName = filePath.endsWith("-definition.yml") ? filePath : `${filePath}-definition.yml`;
    const matches = definitionFiles.filter((definitionFile) => basename(definitionFile) === expectedFileName);
    if (matches.length === 0) {
      throw new Error(`Could not find definition file named ${expectedFileName}.`);
    }
    if (matches.length > 1) {
      throw new Error(`Definition file name ${expectedFileName} is ambiguous:\n${matches.map((match) => `- ${match}`).join("\n")}`);
    }
    return matches[0];
  });
}

async function resolveLocalDevSourceRef(): Promise<string> {
  const override = process.env.RAVION_LOCAL_DEV_SOURCE_REF || process.env.SOURCE_REF;
  if (override) {
    return override;
  }

  const branch = await getCurrentBranch();
  if (branch && (await originBranchExists(branch))) {
    return branch;
  }

  return "main";
}

async function getCurrentBranch(): Promise<string | undefined> {
  try {
    const { stdout } = await execFileAsync("git", ["branch", "--show-current"]);
    const branch = stdout.trim();
    return branch.length > 0 ? branch : undefined;
  } catch {
    return undefined;
  }
}

async function originBranchExists(branch: string): Promise<boolean> {
  try {
    await execFileAsync("git", ["ls-remote", "--exit-code", "--heads", "origin", branch]);
    return true;
  } catch {
    return false;
  }
}

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return String(error);
}
