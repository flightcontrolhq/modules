#!/usr/bin/env node
import { writeFile } from "node:fs/promises";
import { parseAuthoringDefinitionFile } from "./authoring-schema.js";
import { compileAllDefinitions, compileDefinitionFile } from "./compiler.js";
import { generateDefinitionsFromInventory, readInventoryFile, validateGeneratedDefinitions } from "./generate-definitions.js";
import { createPlannedGitHubReleases, planGitHubReleases, readTagPlanFile } from "./github-releases.js";
import { runMigrationGuardrails } from "./guardrails.js";
import { validateModuleConfig } from "./module-schema.js";
import { createDefaultRavionApiClient, formatPublishPlanMarkdown, isPublishPlanError, loadRemoteInventory, publishDefinitions } from "./publish.js";
import { getReleaseStatuses, validateReleaseStatuses } from "./release.js";
import { createPlannedTags, getCurrentCommit, listExistingTags, planTags } from "./tags.js";

const [, , command, ...args] = process.argv;

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
  const plan = planTags(statuses, await listExistingTags(), targetCommit);
  if (args.includes("--create")) {
    await createPlannedTags(plan);
  }
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
  const compiled = await compileAllDefinitions();
  for (const definition of compiled) {
    validateModuleConfig(definition.module, definition.filePath);
  }
  const client = await createDefaultRavionApiClient();
  const format = getArgValue(args, "--format") ?? "json";
  const outputPath = getArgValue(args, "--output");
  let result;
  try {
    result = await publishDefinitions(compiled, client, { dryRun: !args.includes("--apply"), logger: (message) => console.error(`[publish] ${message}`) });
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
  console.error("Usage: ravion-modules <validate|compile|guardrails|status|tags|github-releases|publish|generate-definitions> <*-definition.yml...>");
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

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return String(error);
}
