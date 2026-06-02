#!/usr/bin/env node
import { parseAuthoringDefinitionFile } from "./authoring-schema.js";
import { compileAllDefinitions, compileDefinitionFile } from "./compiler.js";

const [, , command, ...args] = process.argv;

if (command === "validate") {
  for (const filePath of args) {
    await parseAuthoringDefinitionFile(filePath);
  }
} else if (command === "compile") {
  const compiled = args.length > 0 ? await Promise.all(args.map((filePath) => compileDefinitionFile(filePath))) : await compileAllDefinitions();
  console.log(JSON.stringify(compiled, null, 2));
} else {
  console.error("Usage: ravion-modules <validate|compile> <definition.yml...>");
  process.exitCode = 1;
}
