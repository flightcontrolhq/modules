import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { type ReleaseStatus } from "./release.js";

const execFileAsync = promisify(execFile);

export type TagPlanAction = "create" | "exists" | "update";

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
  deleteTag(tagName: string): Promise<void>;
  pushTags(refspecs: string[]): Promise<void>;
}

export interface TagPlanOptions {
  overwrite?: boolean;
}

export function getModuleTagName(type: string, version: string): string {
  return `${type}@${version}`;
}

export function planTags(statuses: ReleaseStatus[], existingTags: ExistingTag[], targetCommit: string, options: TagPlanOptions = {}): TagPlanItem[] {
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
      if (options.overwrite) {
        return {
          type: status.type,
          name: status.name,
          version: status.version,
          releaseDescription: status.releaseDescription,
          modulePath: status.modulePath,
          tagName,
          commit: targetCommit,
          action: "update" as const,
          message: `Move ${tagName} from ${existingCommit} to ${targetCommit}.`,
        };
      }

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
    } else if (item.action === "update") {
      await git.deleteTag(item.tagName);
      await git.createAnnotatedTag(item.tagName, item.commit, `${item.tagName}: ${item.type} ${item.version}`);
    }
  }
}

export async function pushPlannedTags(plan: TagPlanItem[], git: GitTagClient = defaultGitTagClient): Promise<void> {
  const refspecs = plan
    .filter((item) => item.action === "create" || item.action === "update")
    .map((item) => `${item.action === "update" ? "+" : ""}refs/tags/${item.tagName}:refs/tags/${item.tagName}`);
  if (refspecs.length > 0) {
    await git.pushTags(refspecs);
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
  async deleteTag(tagName) {
    await execFileAsync("git", ["tag", "-d", tagName]);
  },
  async pushTags(refspecs) {
    await execFileAsync("git", ["push", "origin", ...refspecs]);
  },
};

function formatTagPlanConflicts(conflicts: TagPlanItem[]): string {
  const formatted = conflicts.map((item) => `- ${item.tagName}: ${item.message}`).join("\n");
  return `Tag planning failed:\n${formatted}`;
}
