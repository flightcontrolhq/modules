import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { type ReleaseStatus } from "./release.js";

const execFileAsync = promisify(execFile);

export type TagPlanAction = "create" | "exists";

export interface ExistingTag {
  name: string;
  commit: string;
}

export interface TagPlanItem {
  type: string;
  name: string;
  version: string;
  releaseDescription: string;
  modulePath: string;
  tagName: string;
  commit: string;
  action: TagPlanAction;
  message: string;
}

export class TagPlanError extends Error {
  readonly conflicts: TagPlanItem[];

  constructor(conflicts: TagPlanItem[]) {
    super(formatTagPlanConflicts(conflicts));
    this.name = "TagPlanError";
    this.conflicts = conflicts;
  }
}

export interface GitTagClient {
  createAnnotatedTag(tagName: string, commit: string, message: string): Promise<void>;
}

export function getModuleTagName(type: string, version: string): string {
  return `${type}@${version}`;
}

export function planTags(statuses: ReleaseStatus[], existingTags: ExistingTag[], targetCommit: string): TagPlanItem[] {
  const existingTagsByName = new Map(existingTags.map((tag) => [tag.name, tag.commit]));
  const publishStatuses = statuses.filter((status) => status.publishState === "unpublished");
  const plan = publishStatuses.map((status) => {
    const tagName = getModuleTagName(status.type, status.version);
    const existingCommit = existingTagsByName.get(tagName);

    if (!existingCommit) {
      return {
        type: status.type,
        name: status.name,
        version: status.version,
        releaseDescription: status.releaseDescription,
        modulePath: status.modulePath,
        tagName,
        commit: targetCommit,
        action: "create" as const,
        message: `Create ${tagName} at ${targetCommit}.`,
      };
    }

    if (existingCommit !== targetCommit) {
      return {
        type: status.type,
        name: status.name,
        version: status.version,
        releaseDescription: status.releaseDescription,
        modulePath: status.modulePath,
        tagName,
        commit: existingCommit,
        action: "exists" as const,
        message: `Tag ${tagName} already points at ${existingCommit}, not ${targetCommit}.`,
      };
    }

    return {
      type: status.type,
      name: status.name,
      version: status.version,
      releaseDescription: status.releaseDescription,
      modulePath: status.modulePath,
      tagName,
      commit: targetCommit,
      action: "exists" as const,
      message: `Tag ${tagName} already points at ${targetCommit}.`,
    };
  });

  const conflicts = plan.filter((item) => item.action === "exists" && item.commit !== targetCommit);
  if (conflicts.length > 0) {
    throw new TagPlanError(conflicts);
  }

  return plan.sort((left, right) => left.tagName.localeCompare(right.tagName));
}

export async function createPlannedTags(plan: TagPlanItem[], git: GitTagClient = defaultGitTagClient): Promise<void> {
  for (const item of plan) {
    if (item.action === "create") {
      await git.createAnnotatedTag(item.tagName, item.commit, `${item.tagName}: ${item.type} ${item.version}`);
    }
  }
}

export async function getCurrentCommit(): Promise<string> {
  const { stdout } = await execFileAsync("git", ["rev-parse", "HEAD"]);
  return stdout.trim();
}

export async function listExistingTags(): Promise<ExistingTag[]> {
  const { stdout } = await execFileAsync("git", ["for-each-ref", "refs/tags", "--format=%(refname:short)%09%(objectname)%09%(*objectname)"]);
  return stdout
    .trim()
    .split("\n")
    .filter((line) => line.length > 0)
    .map((line) => {
      const [name, objectCommit, peeledCommit] = line.split("\t");
      return { name, commit: peeledCommit || objectCommit };
    });
}

const defaultGitTagClient: GitTagClient = {
  async createAnnotatedTag(tagName, commit, message) {
    await execFileAsync("git", ["tag", "-a", tagName, commit, "-m", message]);
  },
};

function formatTagPlanConflicts(conflicts: TagPlanItem[]): string {
  const formatted = conflicts.map((item) => `- ${item.tagName}: ${item.message}`).join("\n");
  return `Tag planning failed:\n${formatted}`;
}
