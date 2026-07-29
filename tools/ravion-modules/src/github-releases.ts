import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { type TagPlanItem } from "./tags.js";

const execFileAsync = promisify(execFile);

export type GitHubReleaseAction = "create" | "exists";

export interface GitHubReleasePlanItem {
  type: string;
  name: string;
  version: string;
  tagName: string;
  title: string;
  body: string;
  action: GitHubReleaseAction;
}

export interface GitHubReleaseClient {
  releaseExists(tagName: string): Promise<boolean>;
  createRelease(tagName: string, title: string, body: string): Promise<void>;
}

export class GitHubReleasePlanError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GitHubReleasePlanError";
  }
}

export async function readTagPlanFile(filePath: string): Promise<TagPlanItem[]> {
  const parsed = JSON.parse(await readFile(filePath, "utf8")) as unknown;
  if (!Array.isArray(parsed) || !parsed.every(isTagPlanItem)) {
    throw new GitHubReleasePlanError(`${filePath} must contain a JSON array produced by the tags command.`);
  }
  return parsed;
}

export async function planGitHubReleases(tagPlan: TagPlanItem[], client: GitHubReleaseClient = defaultGitHubReleaseClient): Promise<GitHubReleasePlanItem[]> {
  const items: GitHubReleasePlanItem[] = [];
  for (const item of tagPlan) {
    const title = `${item.name} ${item.version}`;
    const body = formatReleaseBody(item);
    items.push({
      type: item.type,
      name: item.name,
      version: item.version,
      tagName: item.tagName,
      title,
      body,
      action: (await client.releaseExists(item.tagName)) ? "exists" : "create",
    });
  }
  return items.sort((left, right) => left.tagName.localeCompare(right.tagName));
}

export async function createPlannedGitHubReleases(plan: GitHubReleasePlanItem[], client: GitHubReleaseClient = defaultGitHubReleaseClient): Promise<void> {
  for (const item of plan) {
    if (item.action === "create") {
      await client.createRelease(item.tagName, item.title, item.body);
    }
  }
}

const defaultGitHubReleaseClient: GitHubReleaseClient = {
  async releaseExists(tagName) {
    try {
      await execFileAsync("gh", ["release", "view", tagName, "--json", "tagName"]);
      return true;
    } catch {
      return false;
    }
  },

  async createRelease(tagName, title, body) {
    await execFileAsync("gh", ["release", "create", tagName, "--title", title, "--notes", body]);
  },
};

function formatReleaseBody(item: TagPlanItem): string {
  return [`## ${item.name} ${item.version}`, "", item.releaseDescription.trim(), "", `Module: \`${item.type}\``, `Path: \`${item.modulePath}\``].join("\n");
}

function isTagPlanItem(value: unknown): value is TagPlanItem {
  if (!isRecord(value)) {
    return false;
  }
  return ["type", "name", "version", "releaseDescription", "modulePath", "tagName", "commit", "action", "message"].every((key) => typeof value[key] === "string");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
