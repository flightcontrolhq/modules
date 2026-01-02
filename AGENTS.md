# AI Agent Guidelines for Ravion Modules

This document provides guidelines for AI agents working with this repository.

## Repository Overview

This is the **Ravion Modules** repository - an OpenTofu/Terraform module library for [Flightcontrol](https://www.flightcontrol.dev/). It contains reusable, enterprise-grade infrastructure modules.

### Directory Structure

```
<category>/<module-name>/
```

**Current Categories:**

| Category | Purpose |
|----------|---------|
| `cache/` | Caching infrastructure (ElastiCache) |
| `cdn/` | Content delivery (CloudFront) |
| `compute/` | Compute resources (EC2, ECS, Lambda, Auto Scaling) |
| `database/` | Database services (RDS, DynamoDB, Aurora) |
| `kubernetes/` | Kubernetes resources |
| `messaging/` | Message queues and notifications (SQS, SNS) |
| `monitoring/` | Observability and alerting (CloudWatch) |
| `networking/` | Network infrastructure (VPC, Security Groups, Load Balancers, Route53) |
| `security/` | Security and access management (IAM, KMS, Secrets Manager) |
| `storage/` | Storage services (S3, EFS, EBS) |

## Module Structure Requirements

Every module **MUST** contain the following files:

| File | Purpose | Requirements |
|------|---------|--------------|
| `variables.tf` | Input variables | All variables with `type`, `description`, and `validation` where applicable |
| `outputs.tf` | Output values | All outputs with `description` |
| `versions.tf` | Version constraints | OpenTofu/Terraform and provider version requirements |
| `README.md` | Module documentation | Usage examples, input/output documentation, requirements |

### File Organization

Each resource type should be defined in its own dedicated file, named after the resource it contains. This improves code organization, readability, and makes it easier to locate specific resources.

**Guidelines:**
- Name files after the primary resource they contain (e.g., `sqs_queue.tf`, `iam_role.tf`, `s3_bucket.tf`)
- Group closely related resources in the same file (e.g., an IAM role and its policy attachments)
- Use `locals.tf` for local values when needed
- Use `data.tf` for data sources when needed

### Example Module Structure

```
networking/vpc/
├── vpc.tf              # aws_vpc resource
├── subnets.tf          # aws_subnet resources
├── internet_gateway.tf # aws_internet_gateway resource
├── nat_gateway.tf      # aws_nat_gateway and aws_eip resources
├── route_tables.tf     # aws_route_table and aws_route resources
├── locals.tf           # Local values
├── data.tf             # Data sources
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

## Enterprise Terraform Standards

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Resources | snake_case | `aws_sqs_queue.main_queue` |
| Variables | snake_case | `queue_name`, `visibility_timeout_seconds` |
| Outputs | snake_case | `queue_arn`, `queue_url` |
| Local values | snake_case | `local.default_tags` |
| Files | lowercase with underscores | `main.tf`, `variables.tf` |

### Variable Requirements

Every variable **MUST** include:

```hcl
variable "example_variable" {
  type        = string
  description = "A clear, concise description of what this variable does."
  default     = "optional-default-value"

  validation {
    condition     = length(var.example_variable) > 0
    error_message = "The example_variable must not be empty."
  }
}
```

- **type**: Always specify explicit types (`string`, `number`, `bool`, `list(string)`, `map(string)`, `object({...})`)
- **description**: Clear, concise explanation of the variable's purpose
- **default**: Include sensible defaults where appropriate; omit for required variables
- **validation**: Add validation blocks for variables that have constraints

### Output Requirements

Every output **MUST** include a description:

```hcl
output "queue_arn" {
  description = "The ARN of the SQS queue."
  value       = aws_sqs_queue.main.arn
}
```

### Version Constraints

The `versions.tf` file must specify:

```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

### Tagging Standards

All taggable resources **MUST** support a `tags` variable and merge with default tags:

```hcl
variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources."
  default     = {}
}

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "messaging/sqs"
  }
  tags = merge(local.default_tags, var.tags)
}

resource "aws_sqs_queue" "main" {
  # ...
  tags = local.tags
}
```

### Security Best Practices

1. **No hardcoded secrets**: Never include passwords, API keys, or sensitive data in code
2. **Least privilege IAM**: IAM policies should grant minimum required permissions
3. **Encryption by default**: Enable encryption for all resources that support it
4. **No wildcard permissions**: Avoid `*` in IAM policies where possible
5. **Secure defaults**: Default variable values should be secure (e.g., encryption enabled)

## Documentation Requirements

### Module README.md

Each module's README must include:

1. **Title and description**: What the module does
2. **Usage example**: Complete, working example
3. **Requirements**: OpenTofu/Terraform and provider versions
4. **Inputs table**: All variables with type, description, default, required
5. **Outputs table**: All outputs with description

Example structure:

```markdown
# Module Name

Brief description of what this module creates.

## Usage

\`\`\`hcl
module "example" {
  source = "git::https://github.com/flightcontrolhq/modules.git//category/module?ref=v1.0.0"

  name = "example"
  # other required inputs
}
\`\`\`

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | The name of the resource | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| arn | The ARN of the created resource |
```

## Critical Reminders

### ALWAYS Update Root README.md

When adding, modifying, or removing modules:

1. **Update the Module Directory table** in the root `README.md`
2. Add new modules with their category, name, description, and status
3. Update status from "Planned" to version number when implemented
4. Remove entries for deleted modules

This is **critical** for maintaining accurate documentation.

### Before Committing

Always run these commands before committing changes:

```bash
# Format all Terraform files
tofu fmt -recursive

# Validate module syntax (run from module directory)
tofu init
tofu validate
```

### When Creating New Modules

1. Create the directory structure: `<category>/<module-name>/`
2. Create all required files: `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`
3. Follow all naming conventions and standards in this document
4. Add validation to variables where applicable
5. Include comprehensive examples in the module README
6. **Update the root README.md Module Directory table**
7. Format and validate before committing

### When Modifying Existing Modules

1. Maintain backward compatibility when possible
2. If breaking changes are necessary, document them clearly
3. Update the module's README if inputs/outputs change
4. Update the root README.md if the module description changes
5. Consider semantic versioning impact (major/minor/patch)

## Versioning Guidelines

Follow [Semantic Versioning](https://semver.org/):

| Change Type | Version Bump | Examples |
|-------------|--------------|----------|
| **MAJOR** | Breaking changes | Removed variable, renamed resource, changed default that affects behavior |
| **MINOR** | New features | New module, new optional variable, new output |
| **PATCH** | Bug fixes | Documentation fix, validation fix, non-breaking default change |

## Testing Requirements

### Minimum Validation

All modules must pass:

```bash
tofu fmt -check -recursive
tofu init
tofu validate
```

### Recommended Testing

- Include example configurations in an `examples/` directory within the module
- Test examples can be validated with `tofu plan`

## Questions?

If you're unsure about any standards or conventions, refer to:

1. This AGENTS.md file
2. Existing modules in this repository as examples
3. [OpenTofu Documentation](https://opentofu.org/docs/)
4. [Terraform Best Practices](https://www.terraform-best-practices.com/)
