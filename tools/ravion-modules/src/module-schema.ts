export interface ModuleSchemaIssue {
  path: string;
  message: string;
}

export class ModuleSchemaError extends Error {
  readonly issues: ModuleSchemaIssue[];

  constructor(filePath: string, issues: ModuleSchemaIssue[]) {
    super(formatIssues(filePath, issues));
    this.name = "ModuleSchemaError";
    this.issues = issues;
  }
}

const ROOT_KEYS = new Set(["inputs", "output", "outputs", "ui", "stack", "build", "deploy", "readme"]);
const INPUT_TYPES = new Set([
  "string",
  "text",
  "json",
  "string_array",
  "array",
  "number",
  "boolean",
  "divider",
  "compound",
  "section",
  "object",
  "object_map",
  "object_array",
  "gitrepo",
  "keyvalue",
  "stack",
  "build",
  "deploy",
]);

export function validateModuleConfig(module: unknown, filePath = "module"): Record<string, unknown> {
  const issues: ModuleSchemaIssue[] = [];

  if (!isRecord(module)) {
    throw new ModuleSchemaError(filePath, [{ path: "$", message: "Module config must be an object." }]);
  }

  for (const key of Object.keys(module)) {
    if (!ROOT_KEYS.has(key)) {
      issues.push({ path: key, message: "Unknown module root section." });
    }
  }

  validateInputs(module.inputs, "inputs", issues);

  if (issues.length > 0) {
    throw new ModuleSchemaError(filePath, issues);
  }

  return module;
}

function validateInputs(value: unknown, path: string, issues: ModuleSchemaIssue[]): void {
  if (value === undefined) {
    return;
  }

  if (!Array.isArray(value)) {
    issues.push({ path, message: "Inputs must be an array when provided." });
    return;
  }

  const inputIds = new Set<string>();
  value.forEach((input, index) => {
    const inputPath = `${path}[${index}]`;
    if (!isRecord(input)) {
      issues.push({ path: inputPath, message: "Input must be an object." });
      return;
    }

    const id = input.id;
    if (typeof id !== "string" || id.trim().length === 0) {
      issues.push({ path: `${inputPath}.id`, message: "Input id must be a non-empty string." });
    } else if (inputIds.has(id)) {
      issues.push({ path: `${inputPath}.id`, message: `Duplicate input id ${id}.` });
    } else {
      inputIds.add(id);
    }

    const type = input.type;
    if (typeof type !== "string" || type.trim().length === 0) {
      issues.push({ path: `${inputPath}.type`, message: "Input type must be a non-empty string." });
    } else if (!INPUT_TYPES.has(type) && !type.startsWith("$ref:")) {
      issues.push({ path: `${inputPath}.type`, message: `Unsupported input type ${type}.` });
    }

    if ("properties" in input) {
      validateInputProperties(input.properties, `${inputPath}.properties`, issues);
    }
  });
}

function validateInputProperties(value: unknown, path: string, issues: ModuleSchemaIssue[]): void {
  if (!isRecord(value)) {
    issues.push({ path, message: "Input properties must be an object when provided." });
    return;
  }

  if ("validation" in value) {
    issues.push({ path: `${path}.validation`, message: "Old input.properties.validation shape is not supported; use current field validation keys." });
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function formatIssues(filePath: string, issues: ModuleSchemaIssue[]): string {
  const formattedIssues = issues.map((issue) => `- ${issue.path}: ${issue.message}`).join("\n");
  return `${filePath} failed canonical module schema validation:\n${formattedIssues}`;
}
