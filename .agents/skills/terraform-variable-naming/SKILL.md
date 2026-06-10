---
name: terraform-variable-naming
description: Establishes naming rules for Terraform variables and Ravion module definition input IDs so user config fields sort clearly and read consistently. Use when adding, renaming, reviewing, or designing Terraform module variables, variables.tf, or *-definition.yml module inputs.
---

# Terraform Variable Naming

## Purpose

Use this skill when Terraform variables or Ravion module definition input IDs become part of a user's config file. The goal is to make fields predictable, sortable, AWS-familiar, and easy to scan.

## Core Rules

- Use `snake_case` for all variable and input IDs.
- Prefer AWS provider/resource terminology where possible.
- Use the module context as the implicit top-level prefix.
- Put the resource, feature, or capability first.
- Boolean fields that turn a feature or capability on or off must end with `_enabled`.
- Boolean fields that control whether the module creates a Terraform-managed companion resource must end with `_creation_enabled`; enabling is different from creating, so plain `_enabled` is reserved for feature/capability toggles.
- Avoid `enable_*` and scoped `*_enable_*` in user-facing variables.
- Avoid `create_*` in user-facing variables; `create` reads wrong when set to false because the resource is actually destroyed. Use noun-first `_creation_enabled` instead.
- Prefer positive booleans over negative booleans.
- Group related fields with the same meaningful prefix.
- Repeat the module subject only when needed to disambiguate multiple resources inside the same module.
- Keep shared platform inputs short when they are already clear: `name`, `region`, `tags`, `vpc_id`, `subnet_ids`.

## Boolean Examples

| Avoid | Prefer |
| --- | --- |
| `enable_nat_gateway` | `nat_gateway_enabled` |
| `enable_flow_logs` | `flow_logs_enabled` |
| `enable_dns_support` | `dns_support_enabled` |
| `enable_dns_hostnames` | `dns_hostnames_enabled` |
| `enable_ipv6` | `ipv6_enabled` |
| `public_alb_enable_https` | `public_alb_https_enabled` |
| `ec2_enable_spot` | `ec2_spot_enabled` |
| `disable_scale_in` | `scale_in_enabled` |
| `create_zone` | `zone_creation_enabled` |
| `create_security_group` | `security_group_creation_enabled` |
| `create_route53_validation_records` | `route53_validation_records_creation_enabled` |
| `create_deploy_role` | `deploy_role_creation_enabled` |

## Prefix Guidance

- In `networking/vpc`, prefer `dns_support_enabled` over `vpc_dns_support_enabled` because the module subject is already VPC.
- In `networking/alb`, prefer `http2_enabled` over `alb_http2_enabled` because the module subject is already ALB.
- In `compute/ecs_cluster`, use prefixes such as `public_alb_*`, `private_alb_*`, `public_nlb_*`, and `private_nlb_*` because the module manages several load balancer resources.
- In nested object inputs, scope names to the object context and keep the local grouping clear.
- For optional companion resources created by the module, keep the noun first and use `_creation_enabled` rather than a `create_` prefix or plain `_enabled`.

## Migration Workflow

1. Identify whether the field is public user config, Terraform-only, or both.
2. Rename public Ravion `id` fields first when compatibility risk is high.
3. Update all `show_when`, stack mapping, README, examples, and references in the same change.
4. If renaming Terraform variables, update every `var.<name>` reference and validation error message.
5. Decide whether a compatibility alias is required based on persisted user config, released module versions, or advanced Terraform variable escape hatches.
6. Run formatting and module definition validation.

## Review Checklist

- Does every feature-toggle boolean end with `_enabled`?
- Is this a feature/capability toggle (`_enabled`) or a Terraform-managed resource existence toggle (`_creation_enabled`)?
- If it controls a Terraform-managed resource, does it use the noun-first `_creation_enabled` form?
- Does the field sort next to related fields?
- Is the noun phrase at the start?
- Is the boolean positive?
- Does the name use AWS terminology when practical?
- Is the module subject omitted unless needed for disambiguation?
- Do Ravion input IDs and Terraform variable names match, or is an intentional mapping documented by the stack config?
- Were `show_when`, README tables, examples, validation messages, and stack mappings updated?
