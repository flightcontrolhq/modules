---
name: module-definition-create
description: Create Ravion module definition source files in this modules repo with the correct colocated file name, definition metadata, release metadata, and handoff to config and README work. Use when adding a new Ravion module definition or when the user provides a module name, type, and description; first inspect similar existing repo definitions and delegate detailed config and README work to the module-definition-config and module-definition-readme skills.
---

# Module Definition Create

Create source-controlled module definition files in this repository. Do not create definitions directly through executor or the Ravion API.

## Scope

1. Create the catalog-level `definition` metadata and `release` metadata in a colocated `<definition.type>-definition.yml` file.
2. Use [`module-definition-config`](../module-definition-config/SKILL.md) to write or expand `module.inputs`, `module.stack`, `module.build`, `module.deploy`, and `module.ui`.
3. Use [`module-definition-readme`](../module-definition-readme/SKILL.md) to write or update `module.readme`.

## File Shape

Module definitions live beside existing Terraform modules:

```text
<category>/<module-name>/<definition.type>-definition.yml
```

Example:

```text
networking/vpc/rvn-aws-network-definition.yml
```

Use this top-level shape:

```yaml
definition:
  type: rvn-example
  name: Example
  description: Short catalog description.
release:
  version: 0.0.1
  description: Initial module definition.
module:
  inputs: []
```

## Field Semantics

- `definition.name` is the human catalog label, such as `ECS Cluster` or `ECS Web Server`.
- `definition.type` is the stable unique module type identifier. If the user says module definition `given id`, map it to `definition.type`; `ModuleDefinition` does not have a `givenId` field.
- `definition.description` is the short catalog summary, not README prose.
- `release.version` is the next authored semantic version for this definition.
- `release.description` is the changelog entry for that version.
- `ModuleInstance.givenId` is separate and must not be used when creating a definition.

## Reference Definitions

Use source-controlled examples as naming, file-shape, release, and identifier baselines. Prefer active first-party definitions under module directories over tool test fixtures.

| Purpose         | Name             | Type / given id   | Description                                                                                                      |
| --------------- | ---------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| VPC network     | `VPC Network`    | `rvn-aws-network` | `Production-ready AWS VPC with public and private subnets, NAT gateways, and compliance-ready flow logs.`        |
| ECS cluster     | `ECS Cluster`    | `rvn-ecs-cluster` | `Production-ready AWS ECS cluster with Fargate, Fargate Spot, optional EC2 capacity, and shared load balancers.` |
| ECS web service | `ECS Web Server` | `rvn-ecs-web`     | `Web server ECS service`                                                                                         |

Known active examples include:

- `networking/vpc/rvn-aws-network-definition.yml`
- `compute/ecs_cluster/rvn-ecs-cluster-definition.yml`
- `compute/ecs_service/rvn-ecs-web-definition.yml`
- `hosting/static_site/rvn-aws-static-definition.yml`
- `security/acm_certificate/rvn-acm-certificate-definition.yml`

When creating a new definition, inspect the closest examples by category, AWS service family, dependency shape, and whether the module is a root infrastructure module, dependency module, or deployable workload. Match existing conventions for `definition.type`, catalog name style, release description style, initial module shell, use of partials, source path naming, and handoff boundaries. If no close match exists, inspect at least two active examples to preserve repository style.

## Creation Workflow

1. Confirm the Terraform module directory exists and contains the required module files before adding a definition.
2. Search this repo for active `*-definition.yml` files outside `tools/ravion-modules/test/fixtures`, identify the closest existing examples, and review them before authoring.
3. Verify no active definition already uses the requested `definition.type`.
4. Normalize the proposed definition fields: title-case service names, keep `definition.type` lowercase kebab-case with the `rvn-` prefix for first-party Ravion modules, and keep descriptions concise.
5. Add `<definition.type>-definition.yml` beside the Terraform module using the top-level `definition`, `release`, and `module` sections.
6. Follow the closest examples for ordering, YAML style, release metadata, module shell shape, partial include style, and source path conventions.
7. Add only a minimal `module` shell unless the user also asked for config or README content.
8. Validate the authored definition with the module publishing tool.

## Validation And Local Publish

From the repository root, build and validate the tooling before publishing:

```bash
make modules-tools-build
node tools/ravion-modules/dist/src/cli.js validate <path-to-definition.yml>
node tools/ravion-modules/dist/src/cli.js compile <path-to-definition.yml>
```

For local development publishes, use the local publishing tool:

```bash
make publish-local-dev MODULE=<definition.type> DRY_RUN=1
make publish-local-dev MODULE=<definition.type>
```

The Makefile loads `.env.local` for publish commands when present. Use `SOURCE_REF=<branch-or-ref>` when local dev should publish a source ref other than the current pushed branch or `main`.

## Description Writing

Write the description as a short catalog summary that tells users what the module creates or manages. Prefer one sentence or a noun phrase, without marketing language, Terraform internals, or implementation-only qualifiers.

## Review Checklist

- The definition lives beside an existing Terraform module as `<definition.type>-definition.yml`.
- Similar active repo definitions were inspected and the new file follows the closest applicable examples.
- No other source-controlled definition uses the same `definition.type`.
- The requested `given id` was applied to `definition.type`, not to an instance field.
- The name and description are catalog-level and concise.
- `release.version` is valid semantic versioning and should not be bumped only for local publishes.
- No executor or direct API workflow is used for creation or local publishing.
- Any needed config or README work is explicitly delegated to the linked skills.
