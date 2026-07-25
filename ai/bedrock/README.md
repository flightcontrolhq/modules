# Amazon Bedrock Module

Configures regional Amazon Bedrock settings for one AWS account. The first supported section is model invocation logging, which creates a CloudWatch Logs destination and a least-privilege IAM role that Bedrock assumes to deliver invocation records.

## Model invocation logging

- Account- and region-wide Bedrock model invocation logging
- CloudWatch Logs destination with configurable retention
- Text logging enabled by default, with optional image, embedding, and video delivery
- Optional customer-managed KMS encryption for the CloudWatch log group
- IAM trust policy restricted by AWS account and regional Bedrock source ARN
- Tags on the CloudWatch log group and IAM role

## Important behavior

Amazon Bedrock supports one model invocation logging configuration per AWS account and region. Do not deploy this module more than once for the same account and region or manage the same configuration from another Terraform state.

Destroying this module deletes the regional logging configuration and stops future invocation log delivery. Existing CloudWatch logs remain subject to the log group's normal Terraform destruction behavior.

Invocation logs can contain full model inputs and outputs. Treat the log group as sensitive data, restrict access, choose an appropriate retention period, and use a customer-managed KMS key when your security requirements call for it.

Model invocation logging covers supported calls to the `bedrock-runtime` endpoint, including `Converse`, `ConverseStream`, `InvokeModel`, and `InvokeModelWithResponseStream`. It does not currently capture calls made through the `bedrock-mantle` endpoint.

## Module scope

This module is the shared Terraform source for Amazon Bedrock capabilities in an AWS account and region. Model invocation logging is the first supported section. Future capabilities—including prompts, guardrails, inference profiles, custom models, agents, flows, and knowledge bases—belong in this same module as optional sections.

The long-term module surface should track the Bedrock resources exposed by the AWS Terraform provider. Each release must clearly distinguish implemented sections from provider capabilities that are still planned.

Follow the repository's ECS module pattern when extending it:

- Keep one Terraform source module at `ai/bedrock`.
- Put each Bedrock capability in its own `.tf` file and variable/output section.
- Model repeatable resources such as prompts and guardrails as keyed maps and create them with `for_each`.
- Add Ravion definition variants over the same source module only when a simpler use-case-specific experience is useful.
- Keep account- and region-wide singleton resources, such as model invocation logging, unique within the module.

## Usage

```hcl
module "bedrock" {
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.1.0"

  name   = "ravion-prod"
  region = "us-west-2"

  model_invocation_logging_enabled = true
  text_data_delivery_enabled       = true
  log_group_retention_days         = 90

  tags = {
    Environment = "production"
    Owner       = "platform"
  }
}
```

### Enable additional modalities

```hcl
module "bedrock" {
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.1.0"

  name   = "ai-prod"
  region = "us-west-2"

  text_data_delivery_enabled      = true
  image_data_delivery_enabled     = true
  embedding_data_delivery_enabled = true
  video_data_delivery_enabled     = false
}
```

### Import an existing regional configuration

If model invocation logging is already enabled outside this module, import the regional configuration instead of attempting to create it:

```hcl
import {
  to = aws_bedrock_model_invocation_logging_configuration.this[0]
  id = "us-west-2"
}
```

The CloudWatch log group and IAM role must also be brought under the same Terraform state or replaced during a controlled migration.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for resources created by the module | `string` | n/a | yes |
| region | AWS region where Amazon Bedrock is configured | `string` | Provider region | no |
| model_invocation_logging_enabled | Enable regional Bedrock model invocation logging | `bool` | `true` | no |
| text_data_delivery_enabled | Include text inputs and outputs in invocation logs | `bool` | `true` | no |
| image_data_delivery_enabled | Include image inputs and outputs in invocation logs | `bool` | `false` | no |
| embedding_data_delivery_enabled | Include embedding inputs and outputs in invocation logs | `bool` | `false` | no |
| video_data_delivery_enabled | Include video inputs and outputs in invocation logs | `bool` | `false` | no |
| log_group_name | Name of the CloudWatch log group to create | `string` | `/aws/bedrock/model-invocations/<name>` | no |
| log_group_retention_days | Number of days to retain invocation logs; use 0 for indefinite retention | `number` | `90` | no |
| log_group_kms_key_arn | Optional customer-managed KMS key ARN for the CloudWatch log group | `string` | `null` | no |
| tags | Additional tags for resources created by the module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| model_invocation_logging_configuration_id | Region identifying the Bedrock model invocation logging configuration; null if disabled |
| model_invocation_log_group_name | CloudWatch log group name; null if disabled |
| model_invocation_log_group_arn | CloudWatch log group ARN; null if disabled |
| model_invocation_logging_role_arn | IAM role ARN used by Bedrock for log delivery; null if disabled |
| aws_account_id | AWS account ID where logging is configured |
| region | AWS region where logging is configured |

## KMS key policy

When `log_group_kms_key_arn` is set, the KMS key policy must allow the regional CloudWatch Logs service principal to use the key. See the AWS CloudWatch Logs documentation for the required key policy.

## Learn more

- [Amazon Bedrock model invocation logging](https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html)
- [Terraform AWS provider resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_model_invocation_logging_configuration)
