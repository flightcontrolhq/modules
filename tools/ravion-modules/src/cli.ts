#!/usr/bin/env node
import { parseAuthoringDefinitionFile } from "./authoring-schema.js";
import { compileAllDefinitions, compileDefinitionFile } from "./compiler.js";
import { generateDefinitionsFromInventory, readInventoryFile, validateGeneratedDefinitions } from "./generate-definitions.js";
import { validateModuleConfig } from "./module-schema.js";
import { createDefaultRavionApiClient, loadRemoteInventory, publishDefinitions } from "./publish.js";
import { getReleaseStatuses, validateReleaseStatuses } from "./release.js";
import { createPlannedTags, getCurrentCommit, listExistingTags, planTags } from "./tags.js";

const [, , command, ...args] = process.argv;

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
} else if (command === "publish") {
  const compiled = await compileAllDefinitions();
  for (const definition of compiled) {
    validateModuleConfig(definition.module, definition.filePath);
  }
  const client = await createDefaultRavionApiClient();
  const result = await publishDefinitions(compiled, client, { dryRun: !args.includes("--apply") });
  console.log(JSON.stringify(result, null, 2));
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
  console.error("Usage: ravion-modules <validate|compile|status|tags|publish|generate-definitions> <definition.yml...>");
  process.exitCode = 1;
}
