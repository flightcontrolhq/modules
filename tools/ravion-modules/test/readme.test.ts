import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { compileAllDefinitions } from "../src/compiler.js";
import { README_TABLE_BEGIN_MARKER, README_TABLE_END_MARKER, ReadmeSyncError, renderModuleDefinitionsTable, syncReadme, updateReadmeContent } from "../src/readme.js";

const repoRoot = resolve("../..");

test("renders one sorted row per definition with its release version", async () => {
  const compiled = await compileAllDefinitions(repoRoot);
  const table = renderModuleDefinitionsTable(compiled, repoRoot);
  const rows = table.split("\n").slice(2);

  assert.equal(rows.length, compiled.length);
  const types = rows.map((row) => row.split("|")[1].trim().replaceAll("`", ""));
  assert.deepEqual(types, [...types].sort((left, right) => left.localeCompare(right)));

  for (const definition of compiled) {
    assert.ok(
      rows.some((row) => row.includes(`\`${definition.type}\``) && row.includes(`v${definition.version}`)),
      `expected a row for ${definition.type}@${definition.version}`,
    );
  }
});

test("replaces only the content between the generated markers", () => {
  const readme = `# Title\n\nintro\n\n${README_TABLE_BEGIN_MARKER}\n\nstale\n\n${README_TABLE_END_MARKER}\n\noutro\n`;
  const updated = updateReadmeContent(readme, "| Definition |\n| ---------- |\n| `rvn-s3` |");

  assert.ok(updated.startsWith("# Title\n\nintro\n"));
  assert.ok(updated.endsWith(`${README_TABLE_END_MARKER}\n\noutro\n`));
  assert.ok(updated.includes("| `rvn-s3` |"));
  assert.ok(!updated.includes("stale"));
});

test("fails when the markers are missing", () => {
  assert.throws(() => updateReadmeContent("# Title\n", "| Definition |"), ReadmeSyncError);
});

test("repository README is in sync with the definition versions", async () => {
  const result = await syncReadme({ rootPath: repoRoot });
  assert.equal(result.changed, false, "run `node tools/ravion-modules/dist/src/cli.js readme` and commit the result");
  assert.equal(result.content, await readFile(result.readmePath, "utf8"));
});
