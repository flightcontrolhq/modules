import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { type ReleaseStatus } from "../src/release.js";
import { createPlannedTags, getModuleTagName, planTags, TagPlanError } from "../src/tags.js";

describe("release tags", () => {
  it("generates module-scoped tag names from module types and versions", () => {
    assert.equal(getModuleTagName("ravion-aws-vpc", "1.2.3"), "ravion-aws-vpc@1.2.3");
  });

  it("plans tags only for unpublished versions", () => {
    const plan = planTags(
      [createStatus({ type: "ravion-aws-vpc", publishState: "unpublished" }), createStatus({ type: "ravion-aws-rds", publishState: "published" })],
      [],
      "abc123",
    );

    assert.deepEqual(plan.map(({ tagName, name, releaseDescription, modulePath, action, commit }) => ({ tagName, name, releaseDescription, modulePath, action, commit })), [
      {
        tagName: "ravion-aws-vpc@1.2.3",
        name: "AWS VPC",
        releaseDescription: "Add subnet options.",
        modulePath: "networking/vpc",
        action: "create",
        commit: "abc123",
      },
    ]);
  });

  it("detects existing matching tags", () => {
    const plan = planTags([createStatus({ type: "ravion-aws-vpc", publishState: "unpublished" })], [{ name: "ravion-aws-vpc@1.2.3", commit: "abc123" }], "abc123");

    assert.deepEqual(plan.map(({ tagName, action, commit }) => ({ tagName, action, commit })), [
      { tagName: "ravion-aws-vpc@1.2.3", action: "exists", commit: "abc123" },
    ]);
  });

  it("fails if an existing tag points to a different commit", () => {
    assert.throws(
      () => planTags([createStatus({ type: "ravion-aws-vpc", publishState: "unpublished" })], [{ name: "ravion-aws-vpc@1.2.3", commit: "def456" }], "abc123"),
      (error) => error instanceof TagPlanError && error.message.includes("ravion-aws-vpc@1.2.3") && error.message.includes("def456"),
    );
  });

  it("creates only missing tags as annotated tags", async () => {
    const created: Array<{ tagName: string; commit: string; message: string }> = [];
    const plan = [
      ...planTags([createStatus({ type: "ravion-aws-vpc", publishState: "unpublished" })], [], "abc123"),
      ...planTags([createStatus({ type: "ravion-aws-rds", publishState: "unpublished" })], [{ name: "ravion-aws-rds@1.2.3", commit: "abc123" }], "abc123"),
    ];

    await createPlannedTags(plan, {
      async createAnnotatedTag(tagName, commit, message) {
        created.push({ tagName, commit, message });
      },
    });

    assert.deepEqual(created, [{ tagName: "ravion-aws-vpc@1.2.3", commit: "abc123", message: "ravion-aws-vpc@1.2.3: ravion-aws-vpc 1.2.3" }]);
  });
});

function createStatus(overrides: Partial<ReleaseStatus>): ReleaseStatus {
  return {
    type: "ravion-aws-vpc",
    name: "AWS VPC",
    version: "1.2.3",
    releaseDescription: "Add subnet options.",
    filePath: join("/repo", "networking", "vpc", "ravion-aws-vpc-definition.yml"),
    modulePath: "networking/vpc",
    publishState: "unpublished",
    message: "Release version does not exist remotely yet.",
    ...overrides,
  };
}
