import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import YAML from "yaml";

test("module definition workflow has valid syntax and expected jobs", async () => {
  const workflowPath = resolve("../../.github/workflows/module-definitions.yml");
  const workflow = YAML.parse(await readFile(workflowPath, "utf8")) as Record<string, unknown>;

  assert.equal(workflow.name, "Module Definitions");
  assert.deepEqual(workflow.on, {
    pull_request: { branches: ["main"] },
    push: { branches: ["main"] },
  });

  const jobs = workflow.jobs as Record<string, { permissions?: Record<string, string>; steps: Array<Record<string, unknown>> }>;
  assert.ok(jobs.validate);
  assert.ok(jobs.publish);
  assert.deepEqual(jobs.publish.permissions, { contents: "write" });
  assert.ok(jobs.publish.steps.some((step) => step.run === "node dist/src/cli.js tags --api --create"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node dist/src/cli.js publish --apply"));
});
