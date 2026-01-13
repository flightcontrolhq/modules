# AWS IAM Role

Creates a flexible AWS IAM role with support for multiple trust relationship types, managed and inline policies, permission boundaries, and optional instance profiles.

## Features

- Multiple trust relationship types: AWS services, AWS principals, OIDC providers, SAML providers
- Attach managed policies (AWS or customer managed)
- Inline policies via JSON or structured statements
- Optional permission boundary
- Optional IAM instance profile for EC2
- Comprehensive input validation
- Flexible naming (name or name_prefix)

## Usage

### Basic Usage - ECS Task Role

```hcl
module "ecs_task_role" {
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//security/iam?ref=v1.0.0"

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

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

### General

| Name                   | Description                                                                    | Type          | Default                  | Required |
| ---------------------- | ------------------------------------------------------------------------------ | ------------- | ------------------------ | :------: |
| name                   | The name of the IAM role. Mutually exclusive with name_prefix.                 | `string`      | `null`                   |    no    |
| name_prefix            | Creates a unique name beginning with the specified prefix.                     | `string`      | `null`                   |    no    |
| description            | The description of the IAM role.                                               | `string`      | `"Managed by Terraform"` |    no    |
| path                   | The path to the IAM role.                                                      | `string`      | `"/"`                    |    no    |
| max_session_duration   | The maximum session duration (in seconds) for the IAM role (3600-43200).       | `number`      | `3600`                   |    no    |
| force_detach_policies  | Whether to force detaching any policies the role has before destroying it.     | `bool`        | `true`                   |    no    |
| tags                   | A map of tags to assign to all resources.                                      | `map(string)` | `{}`                     |    no    |

### Assume Role Policy - Trust Relationships

| Name                     | Description                                                                                | Type                          | Default | Required |
| ------------------------ | ------------------------------------------------------------------------------------------ | ----------------------------- | ------- | :------: |
| trusted_services         | List of AWS service principals that can assume this role.                                  | `list(string)`                | `[]`    |    no    |
| trusted_aws_principals   | List of AWS account IDs or ARNs that can assume this role.                                 | `list(string)`                | `[]`    |    no    |
| trusted_oidc_providers   | List of OIDC identity providers that can assume this role. See usage examples.             | `list(object({...}))`         | `[]`    |    no    |
| trusted_saml_providers   | List of SAML provider ARNs that can assume this role.                                      | `list(string)`                | `[]`    |    no    |
| assume_role_conditions   | Additional conditions to apply to all trust policy statements.                             | `list(object({...}))`         | `[]`    |    no    |
| custom_assume_role_policy| A custom assume role policy JSON document. Overrides all other trust policy settings.     | `string`                      | `null`  |    no    |

### Policy Attachments

| Name                | Description                                                 | Type           | Default | Required |
| ------------------- | ----------------------------------------------------------- | -------------- | ------- | :------: |
| managed_policy_arns | List of managed policy ARNs to attach to the role.          | `list(string)` | `[]`    |    no    |

### Inline Policies

| Name                      | Description                                                    | Type                  | Default | Required |
| ------------------------- | -------------------------------------------------------------- | --------------------- | ------- | :------: |
| inline_policies           | Map of inline policy names to JSON policy documents.           | `map(string)`         | `{}`    |    no    |
| inline_policy_statements  | List of inline policy statements to combine into a policy.     | `list(object({...}))` | `[]`    |    no    |

### Permission Boundary

| Name                    | Description                                                                    | Type     | Default | Required |
| ----------------------- | ------------------------------------------------------------------------------ | -------- | ------- | :------: |
| permission_boundary_arn | The ARN of the policy that is used to set the permissions boundary.            | `string` | `null`  |    no    |

### Instance Profile

| Name                    | Description                                                              | Type     | Default | Required |
| ----------------------- | ------------------------------------------------------------------------ | -------- | ------- | :------: |
| create_instance_profile | Whether to create an IAM instance profile for this role.                 | `bool`   | `false` |    no    |
| instance_profile_name   | The name of the instance profile. Defaults to the role name.             | `string` | `null`  |    no    |
| instance_profile_path   | The path to the instance profile. Defaults to the role path.             | `string` | `null`  |    no    |

## Outputs

### IAM Role

| Name             | Description                                  |
| ---------------- | -------------------------------------------- |
| role_arn         | The ARN of the IAM role.                     |
| role_name        | The name of the IAM role.                    |
| role_id          | The stable unique ID of the IAM role.        |
| role_unique_id   | The unique ID assigned by AWS to the role.   |
| role_path        | The path of the IAM role.                    |
| role_create_date | The creation timestamp of the IAM role.      |

### Instance Profile

| Name                       | Description                                                        |
| -------------------------- | ------------------------------------------------------------------ |
| instance_profile_arn       | The ARN of the IAM instance profile (null if not created).         |
| instance_profile_name      | The name of the IAM instance profile (null if not created).        |
| instance_profile_id        | The ID of the IAM instance profile (null if not created).          |
| instance_profile_unique_id | The unique ID of the IAM instance profile (null if not created).   |

### Policy Information

| Name                | Description                                        |
| ------------------- | -------------------------------------------------- |
| managed_policy_arns | List of managed policy ARNs attached to the role.  |
| inline_policy_names | List of inline policy names attached to the role.  |

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

| Type                       | Use Case                                          | Action                         |
| -------------------------- | ------------------------------------------------- | ------------------------------ |
| `trusted_services`         | AWS services (ECS, Lambda, EC2, etc.)             | `sts:AssumeRole`               |
| `trusted_aws_principals`   | Cross-account access, specific IAM entities       | `sts:AssumeRole`               |
| `trusted_oidc_providers`   | GitHub Actions, EKS pods, external IdPs           | `sts:AssumeRoleWithWebIdentity`|
| `trusted_saml_providers`   | Enterprise SSO, federated access                  | `sts:AssumeRoleWithSAML`       |

## License

This module is part of the Ravion Modules library and is licensed under the AGPL-3.0 license.
