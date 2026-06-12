export interface LocalDevSourceRefInput {
  override?: string;
  branch?: string;
}

export function selectLocalDevSourceRef(input: LocalDevSourceRefInput): string {
  const override = input.override?.trim();
  if (override) {
    return override;
  }

  const branch = input.branch?.trim();
  if (branch) {
    return branch;
  }

  return "main";
}
