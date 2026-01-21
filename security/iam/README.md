# AWS IAM Role Module

Creates a flexible AWS IAM role with support for multiple trust relationship types, managed and inline policies, permission boundaries, and optional instance profiles.

## Features

- Multiple trust relationship types: AWS services, AWS principals, OIDC providers, SAML providers
- Attach managed policies (AWS or customer managed)
- Inline policies via JSON or structured statements
- Optional permission boundary
- Optional IAM instance profile for EC2
- Comprehensive input validation
- Flexible naming (name or name_prefix)
- Custom assume role policy override support

## Usage

### Basic Usage - ECS Task Role

```hcl
module "ecs_task_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name             = "my-ecs-task-role"
  trusted_services = ["ecs-tasks.amazonaws.com"]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ]
}
```

### Lambda Execution Role

```hcl
module "lambda_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name             = "my-lambda-execution-role"
  trusted_services = ["lambda.amazonaws.com"]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]

  inline_policy_statements = [
    {
      sid       = "AllowDynamoDBAccess"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
      resources = ["arn:aws:dynamodb:*:*:table/my-table"]
    }
  ]
}
```

### EC2 Instance Role with Instance Profile

```hcl
module "ec2_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name                    = "my-ec2-instance-role"
  trusted_services        = ["ec2.amazonaws.com"]
  create_instance_profile = true

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  tags = {
    Environment = "production"
  }
}
```

### GitHub Actions OIDC Role

```hcl
module "github_actions_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name = "github-actions-deploy-role"

  trusted_oidc_providers = [{
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    conditions = [
      {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      },
      {
        test     = "StringLike"
        variable = "token.actions.githubusercontent.com:sub"
        values   = ["repo:my-org/my-repo:*"]
      }
    ]
  }]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  ]
}
```

### Cross-Account Access Role

```hcl
module "cross_account_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name                   = "cross-account-access-role"
  trusted_aws_principals = ["arn:aws:iam::111111111111:root"]

  # Require MFA for assuming this role
  assume_role_conditions = [{
    test     = "Bool"
    variable = "aws:MultiFactorAuthPresent"
    values   = ["true"]
  }]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]
}
```

### EKS Pod Identity Role

```hcl
module "eks_pod_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name = "my-app-pod-role"

  trusted_oidc_providers = [{
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    conditions = [{
      test     = "StringEquals"
      variable = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub"
      values   = ["system:serviceaccount:my-namespace:my-service-account"]
    }]
  }]

  inline_policy_statements = [
    {
      sid       = "AllowS3Access"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
    }
  ]
}
```

### Role with Inline JSON Policy

```hcl
module "role_with_json_policy" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name             = "my-custom-role"
  trusted_services = ["ec2.amazonaws.com"]

  inline_policies = {
    "custom-policy" = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::my-bucket/*"]
      }]
    })
  }
}
```

### Role with Custom Assume Role Policy

```hcl
module "custom_trust_role" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/iam?ref=v1.0.0"

  name = "custom-trust-role"

  # Override all trust policy settings with a custom policy
  custom_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "123456789012"
        }
      }
    }]
  })
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the IAM role. Mutually exclusive with name_prefix. | `string` | `null` | no |
| name_prefix | Creates a unique name beginning with the specified prefix. | `string` | `null` | no |
| description | The description of the IAM role. | `string` | `"Managed by Terraform"` | no |
| path | The path to the IAM role. | `string` | `"/"` | no |
| max_session_duration | The maximum session duration (in seconds) for the IAM role (3600-43200). | `number` | `3600` | no |
| force_detach_policies | Whether to force detaching any policies the role has before destroying it. | `bool` | `true` | no |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |

### Assume Role Policy - Trust Relationships

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| trusted_services | List of AWS service principals that can assume this role. | `list(string)` | `[]` | no |
| trusted_aws_principals | List of AWS account IDs or ARNs that can assume this role. | `list(string)` | `[]` | no |
| trusted_oidc_providers | List of OIDC identity providers that can assume this role. | `list(object({...}))` | `[]` | no |
| trusted_saml_providers | List of SAML provider ARNs that can assume this role. | `list(string)` | `[]` | no |
| assume_role_conditions | Additional conditions to apply to all trust policy statements. | `list(object({...}))` | `[]` | no |
| custom_assume_role_policy | A custom assume role policy JSON document. Overrides all other trust policy settings. | `string` | `null` | no |

### IAM Policies - Managed Policies

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| managed_policy_arns | List of managed policy ARNs to attach to the role. | `list(string)` | `[]` | no |

### IAM Policies - Inline Policies

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| inline_policies | Map of inline policy names to JSON policy documents. | `map(string)` | `{}` | no |
| inline_policy_statements | List of inline policy statements to combine into a policy. | `list(object({...}))` | `[]` | no |

### Permission Boundary

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| permission_boundary_arn | The ARN of the policy that is used to set the permissions boundary. | `string` | `null` | no |

### Instance Profile

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create_instance_profile | Whether to create an IAM instance profile for this role. | `bool` | `false` | no |
| instance_profile_name | The name of the instance profile. Defaults to the role name. | `string` | `null` | no |
| instance_profile_path | The path to the instance profile. Defaults to the role path. | `string` | `null` | no |

## Outputs

### IAM Role

| Name | Description |
|------|-------------|
| role_arn | The ARN of the IAM role. |
| role_name | The name of the IAM role. |
| role_id | The stable unique ID of the IAM role. |
| role_unique_id | The unique ID assigned by AWS to the role. |
| role_path | The path of the IAM role. |
| role_create_date | The creation timestamp of the IAM role. |

### Instance Profile

| Name | Description |
|------|-------------|
| instance_profile_arn | The ARN of the IAM instance profile (null if not created). |
| instance_profile_name | The name of the IAM instance profile (null if not created). |
| instance_profile_id | The ID of the IAM instance profile (null if not created). |
| instance_profile_unique_id | The unique ID of the IAM instance profile (null if not created). |

### Policy Information

| Name | Description |
|------|-------------|
| managed_policy_arns | List of managed policy ARNs attached to the role. |
| inline_policy_names | List of inline policy names attached to the role. |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              AWS IAM Role                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        Trust Policy (Assume Role)                       │  │
│  │  • AWS Services (ECS, Lambda, EC2, etc.)                               │  │
│  │  • AWS Principals (accounts, roles, users)                             │  │
│  │  • OIDC Providers (GitHub Actions, EKS)                                │  │
│  │  • SAML Providers (enterprise SSO)                                     │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                           IAM Role                                      │  │
│  │  • Name, Path, Description                                             │  │
│  │  • Max Session Duration                                                │  │
│  │  • Permission Boundary                                                 │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│         ┌───────────────────────────┼───────────────────────────┐            │
│         ▼                           ▼                           ▼            │
│  ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐   │
│  │  Managed Policies │      │  Inline Policies  │      │ Instance Profile │   │
│  │  • AWS managed    │      │  • JSON documents │      │  (for EC2)       │   │
│  │  • Customer       │      │  • Structured     │      │                  │   │
│  │    managed        │      │    statements     │      │                  │   │
│  └──────────────────┘      └──────────────────┘      └──────────────────┘   │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                         SECURITY/IAM TERRAFORM MODULE                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │      ROLE CONFIG                │   │      PERMISSION BOUNDARY                │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name                      │   │ • description                   │   │ • permission_boundary_arn               │  ║
║  │ • name_prefix               │   │ • path                          │   └─────────────────────────────────────────┘  ║
║  │ • tags                      │   │ • max_session_duration          │                                                 ║
║  └──────────────┬──────────────┘   │ • force_detach_policies         │                                                 ║
║                 │                  └─────────────────────────────────┘                                                 ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "security/iam" }                                     │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ FEATURE FLAGS:                                                                                             │   │  ║
║  │  │ • has_trusted_services         = length(var.trusted_services) > 0                                         │   │  ║
║  │  │ • has_aws_principals           = length(var.trusted_aws_principals) > 0                                   │   │  ║
║  │  │ • has_saml_providers           = length(var.trusted_saml_providers) > 0                                   │   │  ║
║  │  │ • use_custom_policy            = var.custom_assume_role_policy != null                                    │   │  ║
║  │  │ • has_inline_policy_statements = length(var.inline_policy_statements) > 0                                 │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ COMPUTED:                                                                                                  │   │  ║
║  │  │ • assume_role_policy = use_custom_policy ? var.custom_assume_role_policy : data.aws_iam_policy_document   │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                      ASSUME ROLE POLICY CONFIG                                                    │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │                                                                                                                   │  ║
║  │  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌────────────────────────────────────┐  │  ║
║  │  │   TRUSTED SERVICES          │   │   TRUSTED AWS PRINCIPALS        │   │   CUSTOM POLICY                    │  │  ║
║  │  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├────────────────────────────────────┤  │  ║
║  │  │ • trusted_services[]        │   │ • trusted_aws_principals[]      │   │ • custom_assume_role_policy        │  │  ║
║  │  │   (ecs-tasks, lambda,       │   │   (account IDs, IAM ARNs)       │   │   (overrides all others)           │  │  ║
║  │  │    ec2, etc.)               │   │                                 │   │                                    │  │  ║
║  │  │                             │   │                                 │   │                                    │  │  ║
║  │  │   Action: sts:AssumeRole    │   │   Action: sts:AssumeRole        │   │                                    │  │  ║
║  │  └─────────────────────────────┘   └─────────────────────────────────┘   └────────────────────────────────────┘  │  ║
║  │                                                                                                                   │  ║
║  │  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌────────────────────────────────────┐  │  ║
║  │  │   TRUSTED OIDC PROVIDERS    │   │   TRUSTED SAML PROVIDERS        │   │   ASSUME ROLE CONDITIONS           │  │  ║
║  │  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├────────────────────────────────────┤  │  ║
║  │  │ • trusted_oidc_providers[]: │   │ • trusted_saml_providers[]      │   │ • assume_role_conditions[]:        │  │  ║
║  │  │   - provider_arn            │   │   (SAML provider ARNs)          │   │   - test                           │  │  ║
║  │  │   - conditions[]:           │   │                                 │   │   - variable                       │  │  ║
║  │  │     · test                  │   │   Action: sts:AssumeRole        │   │   - values                         │  │  ║
║  │  │     · variable              │   │            WithSAML             │   │                                    │  │  ║
║  │  │     · values                │   │                                 │   │   (applied to all statements)      │  │  ║
║  │  │                             │   │                                 │   │                                    │  │  ║
║  │  │   Action: sts:AssumeRole    │   │                                 │   │                                    │  │  ║
║  │  │           WithWebIdentity   │   │                                 │   │                                    │  │  ║
║  │  └─────────────────────────────┘   └─────────────────────────────────┘   └────────────────────────────────────┘  │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────────────────────┐   ┌────────────────────────────────────────────────────┐  ║
║  │                IAM POLICIES CONFIG                       │   │              INSTANCE PROFILE CONFIG               │  ║
║  ├─────────────────────────────────────────────────────────┤   ├────────────────────────────────────────────────────┤  ║
║  │                                                          │   │ • create_instance_profile                         │  ║
║  │  ┌─────────────────────────┐  ┌────────────────────────┐ │   │ • instance_profile_name                           │  ║
║  │  │   MANAGED POLICIES      │  │   INLINE POLICIES      │ │   │ • instance_profile_path                           │  ║
║  │  ├─────────────────────────┤  ├────────────────────────┤ │   └────────────────────────────────────────────────────┘  ║
║  │  │ • managed_policy_arns[] │  │ • inline_policies{}    │ │                                                          ║
║  │  │   (AWS or customer      │  │   (name => JSON doc)   │ │                                                          ║
║  │  │    managed)             │  │                        │ │                                                          ║
║  │  │                         │  │ • inline_policy_       │ │                                                          ║
║  │  │                         │  │   statements[]:        │ │                                                          ║
║  │  │                         │  │   - sid                │ │                                                          ║
║  │  │                         │  │   - effect             │ │                                                          ║
║  │  │                         │  │   - actions            │ │                                                          ║
║  │  │                         │  │   - resources          │ │                                                          ║
║  │  │                         │  │   - conditions         │ │                                                          ║
║  │  └─────────────────────────┘  └────────────────────────┘ │                                                          ║
║  └─────────────────────────────────────────────────────────┘                                                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │                                       DATA SOURCES                                                               │   ║
║  ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │  data.aws_partition.current          │  data.aws_caller_identity.current  │  data.aws_region.current           │   ║
║  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │                               data.aws_iam_policy_document.assume_role[0]                                        │   ║
║  │                         (conditional: use_custom_policy = false)                                                 │   ║
║  ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ Generates: Trust policy document with dynamic statements for services, AWS principals, OIDC, SAML               │   ║
║  └──────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘   ║
║                                                              │                                                          ║
║                                                              ▼                                                          ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │                                        aws_iam_role.this                                                         │   ║
║  │                                          (CORE RESOURCE)                                                         │   ║
║  ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ • name / name_prefix          • assume_role_policy (from local)                                                  │   ║
║  │ • description                 • max_session_duration                                                             │   ║
║  │ • path                        • force_detach_policies                                                            │   ║
║  │                               • permissions_boundary                                                             │   ║
║  └──────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘   ║
║                                                              │                                                          ║
║              ┌───────────────────────────────────────────────┼───────────────────────────────────────────────┐          ║
║              │                                               │                                               │          ║
║              ▼                                               ▼                                               ▼          ║
║  ┌──────────────────────────────────┐   ┌──────────────────────────────────┐   ┌──────────────────────────────────┐   ║
║  │ aws_iam_role_policy_attachment   │   │     aws_iam_role_policy          │   │   aws_iam_instance_profile       │   ║
║  │          .managed                │   │          .inline                 │   │          .this[0]                │   ║
║  │         (for_each)               │   │         (for_each)               │   │      (count: 0 or 1)             │   ║
║  ├──────────────────────────────────┤   ├──────────────────────────────────┤   ├──────────────────────────────────┤   ║
║  │ Attaches managed policies:       │   │ Creates inline policies:         │   │ Creates instance profile:        │   ║
║  │ • AWS managed policies           │   │ • From inline_policies map       │   │ • For EC2 instances              │   ║
║  │ • Customer managed policies      │   │ • From inline_policy_statements  │   │ • Associates with IAM role       │   ║
║  └──────────────────────────────────┘   └──────────────────────────────────┘   └──────────────────────────────────┘   ║
║                                                              │                                                          ║
║                                         ┌────────────────────┴────────────────────┐                                    ║
║                                         │                                         │                                    ║
║                                         ▼                                         ▼                                    ║
║              ┌──────────────────────────────────────────┐   ┌──────────────────────────────────────────┐              ║
║              │  data.aws_iam_policy_document            │   │      aws_iam_role_policy                 │              ║
║              │        .inline_statements[0]             │   │          .statements[0]                  │              ║
║              │    (count: 0 or 1)                       │   │      (count: 0 or 1)                     │              ║
║              ├──────────────────────────────────────────┤   ├──────────────────────────────────────────┤              ║
║              │ Builds policy from structured statements │   │ Attaches statements policy to role       │              ║
║              │ with dynamic conditions                  │   │ Named: "inline-statements"               │              ║
║              └──────────────────────────────────────────┘   └──────────────────────────────────────────┘              ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │            IAM ROLE                     │   │         INSTANCE PROFILE                │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • role_arn                              │   │ • instance_profile_arn                  │                            ║
║  │ • role_name                             │   │ • instance_profile_name                 │                            ║
║  │ • role_id                               │   │ • instance_profile_id                   │                            ║
║  │ • role_unique_id                        │   │ • instance_profile_unique_id            │                            ║
║  │ • role_path                             │   └─────────────────────────────────────────┘                            ║
║  │ • role_create_date                      │                                                                          ║
║  └─────────────────────────────────────────┘                                                                          ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────────┐                          ║
║  │                              POLICY INFORMATION                                          │                          ║
║  ├─────────────────────────────────────────────────────────────────────────────────────────┤                          ║
║  │ • managed_policy_arns     (list of attached managed policy ARNs)                        │                          ║
║  │ • inline_policy_names     (list of inline policy names)                                 │                          ║
║  └─────────────────────────────────────────────────────────────────────────────────────────┘                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              DATA FLOW DIAGRAM                                                         ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║                                    ┌──────────────────────────────────┐                                               ║
║                                    │    TRUST POLICY VARIABLES        │                                               ║
║                                    ├──────────────────────────────────┤                                               ║
║                                    │ var.trusted_services             │                                               ║
║                                    │ var.trusted_aws_principals       │                                               ║
║                                    │ var.trusted_oidc_providers       │                                               ║
║                                    │ var.trusted_saml_providers       │                                               ║
║                                    │ var.assume_role_conditions       │                                               ║
║                                    │ var.custom_assume_role_policy    │                                               ║
║                                    └───────────────┬──────────────────┘                                               ║
║                                                    │                                                                   ║
║                                                    ▼                                                                   ║
║  var.custom_assume_role_policy ──────► data.aws_iam_policy_document.assume_role[0]                                   ║
║              │                                     │                                                                   ║
║              │                                     ▼                                                                   ║
║              └──────────────────────► local.assume_role_policy                                                        ║
║                                                    │                                                                   ║
║                                                    ▼                                                                   ║
║                              ┌──────────────────────────────────────────────────────────┐                             ║
║  var.name ──────────────────►│                                                          │                             ║
║  var.name_prefix ───────────►│                                                          │                             ║
║  var.description ───────────►│                                                          │                             ║
║  var.path ──────────────────►│              aws_iam_role.this                           │                             ║
║  var.max_session_duration ──►│                                                          │                             ║
║  var.force_detach_policies ─►│                                                          │                             ║
║  var.permission_boundary_arn►│                                                          │                             ║
║  local.tags ────────────────►│                                                          │                             ║
║                              └────────────────────────────┬─────────────────────────────┘                             ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────────────────────┐            ║
║           │                                               │                                               │            ║
║           ▼                                               ▼                                               ▼            ║
║  var.managed_policy_arns                    var.inline_policies                   var.create_instance_profile          ║
║           │                                 var.inline_policy_statements                    │                          ║
║           ▼                                               │                                 ▼                          ║
║  aws_iam_role_policy_                                     │                    aws_iam_instance_profile               ║
║  attachment.managed                                       │                         .this[0]                          ║
║                                                           │                                                            ║
║                               ┌───────────────────────────┴───────────────────────────────┐                            ║
║                               │                                                           │                            ║
║                               ▼                                                           ▼                            ║
║                  aws_iam_role_policy.inline                          data.aws_iam_policy_document.inline_statements    ║
║                               │                                                           │                            ║
║                               │                                                           ▼                            ║
║                               │                                          aws_iam_role_policy.statements                ║
║                               │                                                           │                            ║
║                               └───────────────────────────────────────────────────────────┘                            ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║                                                    MODULE OUTPUTS                                                      ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_iam_role` | 1 | Core IAM role resource |
| `aws_iam_role_policy_attachment` | for_each | Attach managed policies to the role |
| `aws_iam_role_policy` (inline) | for_each | Create inline policies from JSON documents |
| `aws_iam_role_policy` (statements) | 0 or 1 | Create policy from structured statements |
| `aws_iam_instance_profile` | 0 or 1 | Instance profile for EC2 use |
| `data.aws_iam_policy_document` (assume_role) | 0 or 1 | Generate trust policy (unless custom provided) |
| `data.aws_iam_policy_document` (inline_statements) | 0 or 1 | Generate policy from structured statements |

## Variable Object Structures

### trusted_oidc_providers

```hcl
list(object({
  provider_arn = string        # ARN of the OIDC identity provider
  conditions   = list(object({
    test     = string          # Condition operator (e.g., "StringEquals", "StringLike")
    variable = string          # Condition key (e.g., "token.actions.githubusercontent.com:sub")
    values   = list(string)    # Condition values
  }))
}))
```

### assume_role_conditions / inline_policy_statements conditions

```hcl
list(object({
  test     = string            # Condition operator
  variable = string            # Condition key
  values   = list(string)      # Condition values
}))
```

### inline_policy_statements

```hcl
list(object({
  sid        = optional(string)       # Statement ID
  effect     = optional(string)       # "Allow" or "Deny" (default: "Allow")
  actions    = list(string)           # List of IAM actions
  resources  = list(string)           # List of resource ARNs
  conditions = optional(list(object({ # Optional conditions
    test     = string
    variable = string
    values   = list(string)
  })))
}))
```

## Trust Relationship Types

| Type | Use Case | Action |
|------|----------|--------|
| `trusted_services` | AWS services (ECS, Lambda, EC2, etc.) | `sts:AssumeRole` |
| `trusted_aws_principals` | Cross-account access, specific IAM entities | `sts:AssumeRole` |
| `trusted_oidc_providers` | GitHub Actions, EKS pods, external IdPs | `sts:AssumeRoleWithWebIdentity` |
| `trusted_saml_providers` | Enterprise SSO, federated access | `sts:AssumeRoleWithSAML` |

## FAQ

### How do I choose between the different trust relationship types?

The choice depends on who or what needs to assume the role:

| Scenario | Use This | Example |
|----------|----------|---------|
| AWS service needs permissions | `trusted_services` | ECS tasks, Lambda functions, EC2 instances |
| Another AWS account needs access | `trusted_aws_principals` | Cross-account deployments, shared services |
| CI/CD pipeline (GitHub, GitLab) | `trusted_oidc_providers` | GitHub Actions deploying to AWS |
| Kubernetes pods in EKS | `trusted_oidc_providers` | Pod identity for AWS API access |
| Enterprise SSO users | `trusted_saml_providers` | Active Directory federation |

**Example combining multiple trust types:**

```hcl
module "hybrid_role" {
  source = "..."

  name = "hybrid-access-role"

  # Allow Lambda to assume
  trusted_services = ["lambda.amazonaws.com"]

  # Allow specific account
  trusted_aws_principals = ["arn:aws:iam::111111111111:role/DeployRole"]

  # Allow GitHub Actions
  trusted_oidc_providers = [{
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    conditions = [{
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:my-org/*"]
    }]
  }]
}
```

### When should I use inline_policies vs inline_policy_statements?

Both create inline policies, but they serve different use cases:

| Use Case | Use This | Why |
|----------|----------|-----|
| Complex/existing policy JSON | `inline_policies` | Direct JSON, full control |
| Simple permission sets | `inline_policy_statements` | Cleaner HCL, automatic formatting |
| Multiple unrelated policies | `inline_policies` | Separate named policies |
| Related permissions | `inline_policy_statements` | Combined into single policy |

**Example using inline_policy_statements:**

```hcl
inline_policy_statements = [
  {
    sid       = "ReadS3"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
  },
  {
    sid       = "WriteCloudWatch"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/*"]
  }
]
```

**Equivalent using inline_policies:**

```hcl
inline_policies = {
  "combined-policy" = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadS3"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
      },
      {
        Sid      = "WriteCloudWatch"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:*:*:log-group:/aws/lambda/*"]
      }
    ]
  })
}
```

### How do I add conditions to trust policies?

Use `assume_role_conditions` to add conditions that apply to **all** trust statements, or use OIDC provider-specific conditions:

**Global condition (applies to all principals):**

```hcl
module "mfa_required_role" {
  source = "..."

  name                   = "admin-role"
  trusted_aws_principals = ["arn:aws:iam::123456789012:root"]

  # Require MFA for all principals
  assume_role_conditions = [{
    test     = "Bool"
    variable = "aws:MultiFactorAuthPresent"
    values   = ["true"]
  }]
}
```

**OIDC-specific conditions:**

```hcl
module "github_role" {
  source = "..."

  name = "github-deploy-role"

  trusted_oidc_providers = [{
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    conditions = [
      {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      },
      {
        test     = "StringLike"
        variable = "token.actions.githubusercontent.com:sub"
        values   = ["repo:my-org/my-repo:ref:refs/heads/main"]  # Only main branch
      }
    ]
  }]
}
```

### What is a permission boundary and when should I use one?

A permission boundary sets the maximum permissions that an IAM role can have, regardless of its attached policies. It's useful for:

- **Delegated administration**: Allow teams to create roles without exceeding their own permissions
- **Security guardrails**: Prevent accidental over-permissioning
- **Compliance**: Enforce organizational policies

```hcl
module "developer_role" {
  source = "..."

  name             = "developer-role"
  trusted_services = ["lambda.amazonaws.com"]

  # Even if broad policies are attached, this boundary limits effective permissions
  permission_boundary_arn = "arn:aws:iam::123456789012:policy/DeveloperBoundary"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/PowerUserAccess"  # Broad, but bounded
  ]
}
```

### How do I use this role with EC2 instances?

Set `create_instance_profile = true` to create an instance profile that EC2 instances can use:

```hcl
module "ec2_role" {
  source = "..."

  name                    = "web-server-role"
  trusted_services        = ["ec2.amazonaws.com"]
  create_instance_profile = true

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
}

# Use in EC2 instance or launch template
resource "aws_instance" "web" {
  ami                  = "ami-xxx"
  instance_type        = "t3.micro"
  iam_instance_profile = module.ec2_role.instance_profile_name
}
```

## Notes

- When using `custom_assume_role_policy`, all other trust policy variables (`trusted_services`, `trusted_aws_principals`, `trusted_oidc_providers`, `trusted_saml_providers`, `assume_role_conditions`) are ignored
- The module validates all input ARNs and service principals to catch common mistakes early
- Either `name` or `name_prefix` must be provided, but not both
- `inline_policy_statements` are combined into a single policy named "inline-statements"
- SAML trust policies automatically include the required `SAML:aud` condition
- The `force_detach_policies` default of `true` ensures clean destruction of roles with attached policies
- Default tags include `ManagedBy = "terraform"` and `Module = "security/iam"` for resource tracking

## License

This module is part of the Ravion Modules library and is licensed under the AGPL-3.0 license.
