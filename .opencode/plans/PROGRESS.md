## 2026-06-02

- Completed task 1: added the initial `tools/ravion-modules` TypeScript package with authoring schema validation for colocated `definition.yml` files.
- Added fixtures and node:test coverage for valid definitions, missing metadata, invalid semver release metadata, invalid stack source metadata, supported composition directive shapes, and invalid directive shapes.
- Verification passed from `tools/ravion-modules`: `npm run typecheck` and `npm test`.
- Next suggested task: build `ravion-modules compile` on top of `parseAuthoringDefinitionFile` and preserve readable file/path errors through include/template resolution.

- Completed task 2: implemented `ravion-modules compile` with single-file and all-definition compilation, explicit `$include`, `$merge`, `$template`, and `$local.module_tag` resolution, cycle detection, and leaked compiler-token/directive rejection.
- Added compile fixtures and node:test coverage for array splicing, map replacement, map merges, template parameter rendering, Ravion `<< ... >>` template pass-through, stable output ordering, `$local.*` leak failure, include cycle failure, and category-directory discovery.
- Verification passed from `tools/ravion-modules`: `npm run typecheck` and `npm test`.
- Next suggested task: add canonical Flightcontrol module schema validation against compiled output, including duplicate input IDs, unsupported input types, and old `input.properties.validation` shape coverage.

- Completed task 3: added canonical module config validation via `tools/ravion-modules/src/module-schema.ts` and wired the CLI `validate` command to compile definitions before validating canonical output.
- Added node:test coverage for accepted current module shapes, duplicate input IDs, unsupported input types, and the old `input.properties.validation` shape.
- Verification passed from `tools/ravion-modules`: `npm run typecheck` and `npm test`.
- Next suggested task: inventory existing `rvn-` module definitions from Ravion Local and generate colocated self-contained `definition.yml` files where matching Terraform module directories already exist.

- Completed task 4: added `ravion-modules generate-definitions` for converting Ravion Local inventory snapshots into self-contained colocated `definition.yml` files, normalizing module repo source refs to `$local.module_tag`, reporting `rvn-` definitions without matching Terraform module directories, and validating generated definitions after write.
- Added node:test coverage for matching `rvn-` generation, missing-module reporting, no partial/composition directives in generated files, latest-version selection, schema validation, and semantic equivalence after compilation.
- Queried executor Ravion Local during implementation. Current `rvn-` inventory has six matching Terraform module directories (`rvn-aws-network`, `rvn-ecs-cluster`, `rvn-ecs-web`, `rvn-aws-acm-certificate`, `rvn-aws-rds`, `rvn-static`) and one `rvn-stack` definition with no matching Terraform module directory, which should remain a manual follow-up unless a stack module directory is added.
- Verification passed from `tools/ravion-modules`: `npm run typecheck` and `npm test`.
- Next suggested task: validate release metadata during status, compile, and publish, including local release state reporting and remote-version mismatch detection.

- Completed task 5: added release status validation for compiled definitions, including local release version reporting, unpublished/published/conflict remote state calculation from inventory data, and hard failure when a remote version already exists with different compiled config.
- Wired `ravion-modules status` and `ravion-modules compile` through release status validation; `status` accepts `--inventory <inventory.json>` for remote comparison while still reporting local release metadata without inventory.
- Added node:test coverage for unpublished state reporting, published identical-version detection, remote config conflict rejection, and missing unpublished release descriptions.
- Verification passed from `tools/ravion-modules`: `npm run typecheck` and `npm test`.
- Next suggested task: implement tag planning and creation with annotated module-scoped tags, dry-run output, existing-tag detection, and conflict detection for tags pointing at different commits.
