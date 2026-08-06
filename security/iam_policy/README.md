# AWS IAM Policy Module

Creates one reusable customer-managed AWS IAM policy from structured statements or a complete JSON policy document.

## Usage

```hcl
module "application_policy" {
  source = "git::https://github.com/ravionhq/modules.git//security/iam_policy?ref=v1.0.0"

  name        = "application-s3-read"
  description = "Allows the application to read objects from its bucket."

  policy_statements = [{
    sid       = "ReadApplicationObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::application-bucket/*"]
    conditions = [{
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = ["123456789012"]
    }]
  }]

  tags = {
    Environment = "production"
  }
}
```

Use `policy_json` when a complete policy document is more practical. When set, it overrides `policy_statements`.

```hcl
module "custom_policy" {
  source = "git::https://github.com/ravionhq/modules.git//security/iam_policy?ref=v1.0.0"

  name = "custom-policy"
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/example:*"
    }]
  })
}
```

## Structured Statements

Each structured statement must set exactly one of `actions` or `not_actions` and exactly one of `resources` or `not_resources`. `NotAction` and `NotResource` can create broad matches, especially with an `Allow` effect, so prefer positive action and resource lists unless an inverse statement is necessary.

```hcl
policy_statements = [{
  sid           = "DenyOutsideApprovedResources"
  effect        = "Deny"
  actions       = ["s3:*"]
  not_resources = [
    "arn:aws:s3:::approved-bucket",
    "arn:aws:s3:::approved-bucket/*",
  ]
}]
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Customer-managed IAM policy name. | `string` | n/a | yes |
| description | Policy description. AWS does not allow updates after creation. | `string` | `null` | no |
| path | IAM path for the policy. | `string` | `"/"` | no |
| policy_statements | Structured IAM statements. Ignored when `policy_json` is set. | `list(object)` | `[]` | no |
| policy_json | Complete IAM policy JSON document. | `string` | `null` | no |
| region | AWS provider region. IAM resources are global. | `string` | `null` | no |
| tags | Tags to assign to the policy. | `map(string)` | `{}` | no |

At least one structured statement or a raw JSON policy document is required.

## Outputs

| Name | Description |
|------|-------------|
| policy_arn | ARN of the customer-managed IAM policy. |
| policy_id | ID of the customer-managed IAM policy. |
| policy_name | Name of the customer-managed IAM policy. |
| policy_path | Path of the customer-managed IAM policy. |
| attachment_count | Number of entities attached to the policy. |
| aws_account_id | AWS account ID where the policy is created. |
| region | AWS provider region used by the module. |

Attach `policy_arn` to roles through the `security/iam` module's `managed_policy_arns` input, or use it as that module's `permission_boundary_arn`.
