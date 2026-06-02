# Ravion Module Definition Source And Release System

## Project

Create a source-controlled system in the `modules` repository for authoring, composing,
versioning, tagging, validating, and publishing Flightcontrol/Ravion module definitions.

The system must support tens to hundreds of module definitions, explicit reuse of shared
definition fragments without losing author control over placement, independent module
versioning, changelog descriptions for every published version, and post-merge publishing
that pins module source code to stable Git tags instead of unavailable pre-merge commit SHAs.

## Current State

- Terraform/OpenTofu modules live in category/module directories like `networking/vpc` and
  `compute/ecs_cluster`.
- Legacy module definition YAML files have been removed from this repo. New source-controlled
  module definitions should use colocated `definition.yml` files only.
- `modules/module-schema.json` exists but is stale relative to the Flightcontrol schema.
  Current Flightcontrol schema supports additional input types and root sections including
  `section`, `object`, `object_map`, `object_array`, `gitrepo`, `keyvalue`, `stack`, `build`,
  and `deploy`.
- The current Flightcontrol `ModuleStack` schema does not include `stack.source`; adding source
  directly under `module.stack` requires a Flightcontrol schema/runtime update before publishing
  compiled definitions with that field.
- Canonical module schema source lives in `flightcontrol/packages/schemas/modules/tsp` and
  generated validation helpers live under `flightcontrol/packages/schemas/modules/src`.
- Flightcontrol already has `ModuleDefinition` and immutable `ModuleVersion` APIs.
- Ravion Local exposes:
  - `moduleDefinitions.createModuleDefinition`
  - `moduleDefinitions.patchModuleDefinition`
  - `moduleDefinitions.listModuleDefinitions`
  - `moduleVersions.createModuleVersion`
  - `moduleVersions.listModuleVersions`
  - `docs.moduleSchemaReference`
- `ModuleVersion` creation already validates config with `ValidateModuleDataTemplatable`,
  stores normalized JSON, and activates draft definitions transactionally.
- The publish seam should therefore use the existing Ravion API instead of writing directly
  to the database.

## Goals

- Keep module definition source files in this `modules` repo.
- Preserve explicit control over ordering and placement of inputs, UI blocks, stack config,
  build config, deploy config, and other shared fragments.
- Allow shared fragments to represent array items, arrays, maps, map fragments, scalar values,
  and parameterized templates.
- Compile authored module definitions to canonical Flightcontrol module config.
- Validate compiled output against the current Flightcontrol module schema, not the stale
  local `module-schema.json` snapshot.
- Track independent semantic versions per module definition.
- Require a curated changelog description for every published module version.
- Publish changed modules in batches.
- Create stable module-scoped Git tags after merge and use those tags in published module
  source refs.
- Run publishing automatically on every commit to `main`, publishing only module versions that are
  needed.
- Make release and publish operations idempotent and safe to rerun.

## Non-Goals

- Do not replace the Terraform modules themselves.
- Do not bypass existing Ravion API validation.
- Do not implement implicit inheritance where shared config silently lands in fixed places.
- Do not move or overwrite published Git tags.
- Do not make commit messages the source of release descriptions.

## Proposed Directory Layout

```txt
modules/
  partials/
    inputs/
    stack/
    ui/
    build/
    deploy/
    templates/

  networking/vpc/definition.yml
  networking/vpc/CHANGELOG.md
  compute/ecs_cluster/definition.yml
  compute/ecs_cluster/CHANGELOG.md

  tools/ravion-modules/
    package.json
    src/
      cli.ts
      compiler.ts
      validate.ts
      tags.ts
      publish.ts
```

## Authoring Model

Each module definition source file should have repo-only metadata plus a `module` block that
compiles into canonical Flightcontrol module config.

Example:

```yaml
definition:
  type: ravion-aws-vpc
  name: AWS VPC
  description: AWS VPC and subnets

release:
  version: 1.2.0
  description: |
    Add VPC flow log options and support S3 flow log destinations.

module:
  inputs:
    - $include: ../../partials/inputs/name.yml
    - id: region
      type: string
      label: AWS Region
      default: us-west-2
      required: true
      values: "$values:aws/regions.select"
    - $include: ../../partials/inputs/aws-account.yml
    - id: networking
      type: section
      label: Networking
    - id: cidr
      type: string
      label: CIDR Range
      required: true
    - $include: ../../partials/inputs/tags.yml

  stack:
    type: opentofu
    source:
      repo: https://github.com/flightcontrolhq/modules
      ref: $local.module_tag
      base_path: networking/vpc
    pipelines:
      defaults:
        variant: standard
        input:
          source:
            repo: https://github.com/flightcontrolhq/modules
            ref: $local.module_tag
            base_path: networking/vpc
      change:
        pipeline_id: terraform-change
      destroy:
        pipeline_id: terraform-destroy
    ravion_state_backend_workspace: "<< module.given_id >>"
```

`$local.*` values are compile-time-only repo tokens. They are never uploaded to Ravion.
`<< ... >>` values are Ravion runtime templates and must pass through the compiler unchanged.

Built-in `$local.*` values:

- `$local.module_tag`: derived from `definition.type` and `release.version`, for example
  `ravion-aws-vpc@1.2.0`.

Compiled output must contain literal source values in the actual canonical definition fields. It
must not contain any `$local.*` token.

## Composition Semantics

Use explicit composition directives at the exact insertion point.

- `$include` inside an array splices the included array or single item at that position.
- `$include` as a map value replaces that value with the included value.
- `$merge` inside a map merges one or more maps into the current map.
- `$template` loads a parameterized fragment and renders it with `with` values.
- `$local.module_tag` scalar tokens resolve from compiler-provided release metadata.
- Includes are resolved relative to the file that contains the directive.
- Includes must be cycle-detected and fail with a readable path chain.
- Compiled output must not contain repo-only keys or composition directives.
- Compiled output must not contain `$local.*` tokens.
- The compiler must pass Ravion `<< ... >>` templates through unchanged.
- The compiler should preserve authored ordering wherever the canonical schema uses arrays.

Example parameterized fragment usage:

```yaml
- $template: ../../partials/templates/ref-input.yml
  with:
    id: vpc
    type: ravion-aws-vpc
    label: VPC
    outputs:
      vpc_id: VPC ID
      private_subnet_ids: Private Subnet IDs
```

## Release Model

Each module definition owns its pending release metadata directly. There are no separate
change files and no versioning command. Authors update `release.version` and
`release.description` in the same `definition.yml` that contains the module definition.

Release flow:

1. PR changes module Terraform and/or module definition source.
2. PR updates `release.version` and `release.description` for each module that should publish a
   new version.
3. PR CI compiles and validates, but does not publish.
4. On every commit to `main`, the publish workflow compiles all definitions and compares them with
   Ravion's already-published module versions.
5. Publish workflow creates any missing module-scoped Git tags at the current `main` commit.
6. Publish workflow compiles definitions with `$local.module_tag` resolved to the corresponding
   tag wherever authors explicitly referenced it.
7. Publish workflow creates only needed `ModuleVersion` rows through the Ravion API using
   `release.version` and `release.description`.
8. If a version already exists with identical compiled config, publish skips it; if it exists with
   different compiled config, publish fails.

## Tag Model

Use module-scoped tags:

```txt
ravion-aws-vpc@1.2.0
ravion-aws-ecs-cluster@1.4.0
ravion-aws-static-site@2.0.0
```

Tag rules:

- Tags are created only after merge, when the final commit exists on `main`.
- Tags point to the current `main` commit being processed by the publish workflow.
- Tags are immutable once pushed.
- If a published version is wrong, publish a new patch version instead of moving the tag.
- Creating many tags on one commit is acceptable. One hundred tags on one commit is not a
  meaningful Git limitation. The workflow should still batch tag creation and pushing to avoid
  noisy partial failures.
- Use annotated tags for all module releases.

## Publish Model

Publishing should be idempotent.

For each compiled module definition:

1. Find `ModuleDefinition` by `definition.type`.
2. Create it if missing.
3. Patch `name` or `description` if metadata changed.
4. List versions for the definition.
5. If `release.version` exists with identical compiled config, skip.
6. If `release.version` exists with different compiled config, fail hard.
7. If missing, create `ModuleVersion` with:
   - `moduleDefinitionId`
   - `release.version`
   - `release.description`
   - compiled canonical config

## Decisions

1. Use explicit composition directives instead of inheritance.

   Options:
   - `extends` inheritance at the file root.
   - YAML anchors.
   - Explicit `$include`, `$merge`, and `$template` directives at insertion points.

   Decision: use explicit directives. Module authors need exact control over input ordering and
   placement. Root-level inheritance hides where shared content lands and makes large definitions
   harder to review.

2. Validate against Flightcontrol's current schema, not `modules/module-schema.json`.

   Options:
   - Keep validating against `modules/module-schema.json`.
   - Vendor a generated schema snapshot.
   - Consume Flightcontrol's generated schema package or API validation.

   Decision: consume Flightcontrol's generated schema package or API validation. The local JSON
   schema is stale and would reject valid current module config or accept old shapes that the app
   no longer supports.

3. Use module-scoped tags as source refs for published versions.

   Options:
   - Publish commit SHAs.
   - Publish branch refs.
   - Publish module-scoped tags.

   Decision: use tags. Commit SHAs are not available on `main` before merge, and branch refs are
   mutable. Tags provide stable source refs for versioned module definitions.

   Tag type decision: use annotated tags for all module releases. Annotated tags carry release
   metadata and are the appropriate Git tag type for release points.

4. Store release metadata in module definition source.

   Options:
   - Store version descriptions in separate change files.
   - Store release metadata only in Ravion API state.
   - Store `release.version` and `release.description` in each module `definition.yml`.

   Decision: store release metadata in source. Each module definition is the release artifact, so
   its version and publish description should be reviewable in the same file without consulting
   separate change files or production API state.

5. Publish through Ravion API instead of direct database writes.

   Options:
   - Write database rows from CI.
   - Use existing API endpoints.

   Decision: use existing API endpoints. The API already handles schema validation, organization
   scoping, draft activation, duplicate version errors, and config normalization.

6. Use `$local.*` for repo-local compile-time tokens.

   Options:
   - Reuse Ravion `<< ... >>` templates for local compile-time substitution.
   - Use a scoped `$local` metadata block.
   - Use a direct scalar token: `$local.module_tag`.

   Decision: use direct `$local.*` scalar tokens. Ravion `<< ... >>` templates must remain the
   actual runtime definition syntax uploaded to Ravion. `$local.*` makes local-only substitution
   visually distinct and easy to reject if it leaks into compiled output. A scoped local block is
   unnecessary for the current authoring model.

## Tasks

- [x] 1. Define the authoring schema for `**/definition.yml` files that live inside existing
     module directories.

  Tests:
  - Add fixtures for valid definitions, invalid missing metadata, invalid release versions, and
    invalid source metadata.
  - Add fixture coverage for every composition directive shape.

  Acceptance criteria:
  - Schema documents repo-only fields and canonical `module` fields.
  - Invalid authoring files fail before publish.
  - Existing canonical Flightcontrol config can be embedded under `module` without losing data.

- [x] 2. Build `ravion-modules compile`.

  Tests:
  - Include array splice tests for `$include`.
  - Include map replacement tests for `$include`.
  - Include map merge tests for `$merge`.
  - Include parameter rendering tests for `$template`.
  - Include `$local.*` resolution tests.
  - Include tests proving Ravion `<< ... >>` templates pass through unchanged.
  - Include tests that fail when `$local.*` remains in compiled output.
  - Include cycle detection tests.
  - Include stable ordering snapshot tests.

  Acceptance criteria:
  - Compiles one definition file to canonical module config.
  - Compiles all definitions found under existing module category directories.
  - Emits readable errors with file paths and YAML paths.
  - Compiled output contains no repo-only metadata, composition directives, or `$local.*` tokens.

- [x] 3. Add canonical module schema validation.

  Tests:
  - Validate compiled fixtures against current Flightcontrol module schema.
  - Add invalid compiled config tests for duplicate input IDs and unsupported input types.

  Acceptance criteria:
  - Validation uses current Flightcontrol schema or an intentionally synced generated artifact.
  - Validation catches old `input.properties.validation` shape.
  - Validation runs locally and in CI.

- [x] 4. Read existing `rvn-` module types from executor Ravion Local and create canonical colocated
     `definition.yml` files without partials.

  Tests:
  - Use executor Ravion Local `moduleDefinitions.listModuleDefinitions` and
    `moduleVersions.listModuleVersions` to inventory existing `rvn-` module definitions and latest
    versions.
  - Compile each generated `definition.yml` without resolving any partials.
  - Validate each generated definition against the current Flightcontrol module schema.
  - Compare generated canonical module config with the Ravion Local latest version config for
    semantic equivalence.

  Acceptance criteria:
  - Every existing `rvn-` module type in Ravion Local has a colocated `definition.yml` in the
    matching module directory when the corresponding Terraform module exists.
  - Generated definitions are canonical and self-contained; they do not use `$include`, `$merge`,
    `$template`, or files under `partials/`.
  - Each generated definition includes `definition.type`, `definition.name`,
    `definition.description`, `release.version`, `release.description`, and `module`.
  - `module.stack.source.ref` and any stack pipeline source ref use `$local.module_tag` when they
    need to point at the released module tag.
  - Modules present in Ravion Local but missing a Terraform module directory are reported for
    manual follow-up instead of creating a new directory silently.

- [x] 5. Validate release metadata during status, compile, and publish.

  Tests:
  - Reject missing `release.version`.
  - Reject invalid semantic versions.
  - Reject missing or empty `release.description` for unpublished versions.
  - Reject publishing when `release.version` already exists remotely with different compiled
    config.

  Acceptance criteria:
  - `ravion-modules status` reports each definition's local release version and remote publish
    state.
  - CI can fail when module definition or Terraform changes would publish without a bumped
    `release.version` and updated `release.description`.
  - No release intent is tracked outside `definition.yml`.

- [ ] 6. Implement tag planning and creation.

  Tests:
  - Generate expected tag names from module types and versions.
  - Detect existing matching tags.
  - Fail if an existing tag points to a different commit for a version being published.

  Acceptance criteria:
  - Tags are created only for versions being published.
  - Tags point at the current `main` commit in the main-branch publish workflow.
  - Tags are annotated tags.
  - The command can run in dry-run mode and show all tags it would create.

- [ ] 7. Implement `ravion-modules publish`.

  Tests:
  - Mock Ravion API list/create/patch definition calls.
  - Mock version creation and duplicate version responses.
  - Test idempotent skip when remote version config matches local compiled config.
  - Test hard failure when remote version exists with different config.
  - Test `release.description` is sent as `ModuleVersion.description`.

  Acceptance criteria:
  - Publishes through Ravion API only.
  - Creates missing definitions.
  - Patches metadata changes.
  - Creates missing versions.
  - Uses `release.version` and `release.description` from `definition.yml`.
  - Never overwrites an existing version.
  - Supports dry-run mode.

- [ ] 8. Add GitHub Actions workflows.

  Tests:
  - Validate workflow syntax.
  - Exercise scripts in dry-run mode in CI.

  Acceptance criteria:
  - PR workflow compiles and validates all definitions.
  - PR workflow validates release metadata for definitions that would publish.
  - Main workflow runs automatically on every commit to `main`.
  - Main workflow creates missing tags for module versions that need publishing.
  - Main workflow publishes any needed module versions idempotently.
  - Main workflow skips already-published identical versions.
  - Main workflow fails on already-published versions whose remote config differs from local
    compiled config.
  - Secrets for Ravion API publishing are used only in the main-branch workflow.

- [ ] 9. Add developer documentation.

  Tests:
  - Documentation examples should be compiled by tests or included as fixtures where practical.

  Acceptance criteria:
  - README explains how to author a definition, include fragments, set `release.version`, write
    `release.description`, and publish.
  - Documentation explains tag immutability and why tags are used instead of pre-merge commits.
  - Documentation lists supported directives and merge semantics.

- [ ] 10. Add migration guardrails.

  Tests:
  - CI fails if legacy module definition YAML files are added.
  - CI fails on duplicate `definition.type` values.

  Acceptance criteria:
  - New module definitions are created beside their Terraform modules.
  - Duplicate module identities are caught before publish.
  - Existing Terraform module validation remains unchanged.

## Open Questions

1. Should publish target global module definitions only, org-scoped definitions only, or both via
   an explicit target flag?
