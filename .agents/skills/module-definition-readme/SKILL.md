---
name: module-definition-readme
description: Write and review Ravion module-definition README content from repo-authored *-definition.yml files and Terraform module behavior. Use when the user asks to create, update, audit, or align README documentation for module definitions, especially content stored in module.readme. This skill explicitly excludes writing or changing module config.
---

# Module Definition README

This skill guides README work for Ravion module definitions. The README is user-facing product documentation embedded in a module definition source file, not the source of truth for module configuration.

## Scope

Use this skill for:

- Writing or revising `module.readme` copy inside a colocated `<definition.type>-definition.yml` file.
- Auditing whether `module.readme` matches the existing module definition inputs and Terraform behavior.
- Explaining feature tradeoffs, use cases, operational implications, and links for a module.

Do not use this skill to write or modify module config, inputs, stack pipeline settings, Terraform variables, defaults, validators, or deployment behavior.

## Source Review

Before writing, inspect these sources in order:

1. The active `<definition.type>-definition.yml` file in this repo.
2. `module.inputs`, including section labels, field labels, defaults, required flags, descriptions, values providers, `show_when`, and nested `item_inputs`.
3. `module.stack.pipelines.defaults.input`, especially `repo`, `ref`, `base_path`, and Terraform variable keys.
4. The Terraform module source README or code only for behavior that is exposed by the module definition or needed to explain user-facing tradeoffs.
5. Existing module-definition READMEs from active nearby `**/*-definition.yml` files to match tone and structure.

Treat `module.inputs` and the module stack mapping as the authority for what the Ravion UI exposes. Treat Terraform source docs as implementation background, not as a complete list of what users can configure in Ravion.

## README Shape

Prefer this structure unless the module clearly needs something different:

1. One-sentence summary matching `definition.description`.
2. `## Overview` explaining what the module creates and why it matters.
3. `## Use cases` as a compact table for scenario-to-benefit mapping.
4. Feature sections for the main concepts users must understand before configuring the module.
5. `## Configuration` covering user-visible inputs, grouped by product concepts rather than raw Terraform internals.
6. Additional sections for complex nested inputs, compliance, observability, capacity, networking, or costs when relevant.
7. `## Design decisions` for opinionated defaults and constraints.
8. `## Learn more` with authoritative external docs.

Keep the README useful for someone choosing settings in the Ravion UI. Avoid Terraform usage examples unless the module definition exposes Terraform-oriented fields directly.

After writing or revising `module.readme`, copy the README's first sentence back into `definition.description` so the catalog summary and embedded README stay aligned. Keep it as a concise plain sentence without markdown formatting.

Keep `module.readme` as the final field inside `module`. The repository field order is `inputs`, `stack`, `build`, `deploy`, `ui`, then `readme` last.

## Config Alignment Rules

- Include only fields exposed by `module.inputs`, plus high-level behavior implied by the stack mapping.
- Use input labels in prose and tables when they are user-facing; mention input IDs only when needed for precision.
- Reflect defaults exactly when they are concrete literals. For template defaults such as `<<project.given_id>>-<<environment.given_id>>`, describe the generated value in human terms.
- Mark required fields from `required: true`. If a field is conditionally required by behavior but not encoded directly, explain the condition in prose.
- Explain nested object inputs in their own section when they contain multiple meaningful fields, such as VPC peering connections.
- Document cost, availability, compliance, or security tradeoffs whenever an input materially changes them.
- Mention advanced or override inputs only briefly unless the target users are expected to use them.
- Do not add fields from the Terraform module README that are not exposed through the module definition.

## Style Rules

- Write in direct, practical language for cloud application teams.
- Prefer short paragraphs, tables for comparisons, and bullets for scanability.
- Explain why a setting matters, not only what it toggles.
- Use sentence case headings except for service names and acronyms.
- Use ASCII punctuation in new content.
- Avoid unsupported promises such as automatic compliance, zero downtime, or guaranteed savings.
- Avoid implementation-only details unless they explain a user decision.

## Validation And Local Publish

After README edits, validate the authored definition:

```bash
make modules-tools-build
node tools/ravion-modules/dist/src/cli.js validate <path-to-definition.yml>
node tools/ravion-modules/dist/src/cli.js compile <path-to-definition.yml>
```

For local development publishes, use the local publishing tool rather than executor:

```bash
make publish-local-dev MODULE=<definition.type> DRY_RUN=1
make publish-local-dev MODULE=<definition.type>
```

Do not bump `release.version` only to publish a new local copy. The local publish tooling automatically appends the next numeric prerelease suffix to the authored version.

## Review Checklist

Before finishing, verify:

- The first sentence matches the module's current purpose and `definition.description`.
- `definition.description` has been updated to the README's first sentence after README edits.
- `module.readme` is the final field inside `module`, after any `inputs`, `stack`, `build`, `deploy`, or `ui` fields.
- Every `Configuration` table row maps to an existing `module.inputs` field or a clearly explained nested field.
- Defaults and required flags match the current definition file.
- Major feature sections correspond to actual exposed inputs or always-on behavior.
- Terraform source links use the stack `repo`, `ref`, and `base_path` when included.
- The README does not instruct the user to edit config, write Terraform, or change pipeline settings.
- The README does not include stale Terraform-only inputs omitted from the module definition.
- Validation passes after the README change.

## Sourcing README References

Find active module-definition README references by filename instead of relying on a fixed list:

```text
**/*-definition.yml
```

Exclude test fixtures and generated files, especially paths under `tools/ravion-modules/test/fixtures`.

When a README needs to describe behavior inherited from a referenced module, source that referenced module by filename. For a `$ref:<module-type>` input, inspect the active file matching `**/<module-type>-definition.yml` and use its `module.inputs`, stack outputs, and README tone as context.

Pick nearby README references by category, AWS service family, dependency model, runtime/deploy model, stack type, and UI complexity. Match their practical tone and table-driven structure without copying stale details or documenting fields that are not exposed by the current definition.
