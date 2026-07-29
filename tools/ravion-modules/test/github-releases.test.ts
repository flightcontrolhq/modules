import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { createPlannedGitHubReleases, planGitHubReleases, type GitHubReleaseClient } from "../src/github-releases.js";
import { type TagPlanItem } from "../src/tags.js";

describe("GitHub releases", () => {
  it("plans releases from tag plan descriptions", async () => {
    const plan = await planGitHubReleases([createTagPlanItem()], createClient());

    assert.deepEqual(plan.map(({ tagName, title, body, action }) => ({ tagName, title, body, action })), [
      {
        tagName: "ravion-aws-vpc@1.2.3",
        title: "AWS VPC 1.2.3",
        body: "## AWS VPC 1.2.3\n\nAdd subnet options.\n\nModule: `ravion-aws-vpc`\nPath: `networking/vpc`",
        action: "create",
      },
    ]);
  });

  it("skips existing releases", async () => {
    const plan = await planGitHubReleases([createTagPlanItem()], createClient({ existingTags: new Set(["ravion-aws-vpc@1.2.3"]) }));

    assert.equal(plan[0].action, "exists");
  });

  it("creates only missing releases", async () => {
    const created: Array<{ tagName: string; title: string; body: string }> = [];
    const client = createClient({ existingTags: new Set(["ravion-aws-rds@1.2.3"]), created });
    const plan = await planGitHubReleases([createTagPlanItem(), createTagPlanItem({ tagName: "ravion-aws-rds@1.2.3", type: "ravion-aws-rds" })], client);

    await createPlannedGitHubReleases(plan, client);

    assert.deepEqual(created.map(({ tagName, title }) => ({ tagName, title })), [{ tagName: "ravion-aws-vpc@1.2.3", title: "AWS VPC 1.2.3" }]);
  });
});

function createTagPlanItem(overrides: Partial<TagPlanItem> = {}): TagPlanItem {
  return {
    type: "ravion-aws-vpc",
    name: "AWS VPC",
    version: "1.2.3",
    releaseDescription: "Add subnet options.",
    modulePath: join("networking", "vpc"),
    tagName: "ravion-aws-vpc@1.2.3",
    commit: "abc123",
    action: "create",
    message: "Create ravion-aws-vpc@1.2.3 at abc123.",
    ...overrides,
  };
}

function createClient(options: { existingTags?: Set<string>; created?: Array<{ tagName: string; title: string; body: string }> } = {}): GitHubReleaseClient {
  return {
    async releaseExists(tagName) {
      return options.existingTags?.has(tagName) ?? false;
    },
    async createRelease(tagName, title, body) {
      options.created?.push({ tagName, title, body });
    },
  };
}
