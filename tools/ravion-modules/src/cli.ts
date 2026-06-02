#!/usr/bin/env node
import { parseAuthoringDefinitionFile } from "./authoring-schema.js";

const [, , command, ...args] = process.argv;

if (command === "validate") {
  for (const filePath of args) {
    await parseAuthoringDefinitionFile(filePath);
  }
} else {
  console.error("Usage: ravion-modules validate <definition.yml...>");
  process.exitCode = 1;
}
