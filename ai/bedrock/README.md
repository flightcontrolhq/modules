# Amazon Bedrock Module

Configures regional Amazon Bedrock settings for one AWS account: model invocation logging, guardrails, application inference profiles, provisioned throughput, custom models, and foundation model access.

Every section is optional and off by default except model invocation logging. Repeatable resources are keyed maps created with `for_each`, so entries can be added and removed without disturbing the others.

## Coverage

This module covers the `aws_bedrock_*` resources in the AWS provider:

| Resource | Module input |
|----------|--------------|
| `aws_bedrock_model_invocation_logging_configuration` | `model_invocation_logging_enabled` |
| `aws_bedrock_guardrail` | `guardrails` |
| `aws_bedrock_guardrail_version` | `guardrails[*].version_creation_enabled` |
| `aws_bedrock_custom_model` | `custom_models` |
| `aws_bedrock_inference_profile` | `inference_profiles` |
| `aws_bedrock_provisioned_model_throughput` | `provisioned_model_throughputs` |
| `aws_bedrock_foundation_model_agreement` | `foundation_model_agreements` |
| `aws_bedrock_use_case_for_model_access` | `model_access_use_case_form_data` |

The `aws_bedrockagent_*` (agents, knowledge bases, data sources, flows, prompts) and `aws_bedrockagentcore_*` (agent runtimes, gateways, memory, browsers, code interpreters) resource families are not implemented yet. See [Module scope](#module-scope).

## Model invocation logging

- Account- and region-wide Bedrock model invocation logging
- CloudWatch Logs destination with configurable retention
- Text logging enabled by default, with optional image, embedding, and video delivery
- Optional customer-managed KMS encryption for the CloudWatch log group
- IAM trust policy restricted by AWS account and regional Bedrock source ARN
- Tags on the CloudWatch log group and IAM role

## Guardrails

Each entry in `guardrails` creates one guardrail. A guardrail must configure at least one filter list; the filter lists are flat so they map directly onto form inputs and onto the provider's policy blocks:

| Input | Provider block |
|-------|----------------|
| `content_filters`, `content_filter_tier` | `content_policy_config` |
| `denied_topics`, `denied_topic_tier` | `topic_policy_config` |
| `denied_words`, `managed_word_lists` | `word_policy_config` |
| `pii_entities`, `regex_filters` | `sensitive_information_policy_config` |
| `grounding_filters` | `contextual_grounding_policy_config` |

Set `version_creation_enabled` to publish an immutable version. A version snapshots the guardrail as it exists when published — later edits to the guardrail do not change an existing version. Change `version_description` to publish a new snapshot.

## Custom models

Each entry in `custom_models` runs one model customization job. Jobs run once, can take hours, and are not re-run when their inputs change — changing a job's configuration replaces it with a new job. The `role_arn` must allow Bedrock to read the training data and write to the output location.

## Provisioned throughput

Reservations without `commitment_duration` bill on demand and can be deleted at any time. Reservations with a commitment term bill for the full term and cannot be cancelled early, so plan changes to committed reservations carefully.

## Model access

`foundation_model_agreements` accepts model agreements for the account and region. The current offer token is resolved automatically through the `aws_bedrock_foundation_model_agreement_offers` data source unless you pin `offer_token` yourself. Models that require an approved use case, such as the Anthropic models, also need `model_access_use_case_form_data`; the module submits that form before accepting any agreement.

## Important behavior

Amazon Bedrock supports one model invocation logging configuration per AWS account and region. Do not deploy this module more than once for the same account and region or manage the same configuration from another Terraform state.

Destroying this module deletes the regional logging configuration and stops future invocation log delivery. Existing CloudWatch logs remain subject to the log group's normal Terraform destruction behavior.

Invocation logs can contain full model inputs and outputs. Treat the log group as sensitive data, restrict access, choose an appropriate retention period, and use a customer-managed KMS key when your security requirements call for it.

Model invocation logging covers supported calls to the `bedrock-runtime` endpoint, including `Converse`, `ConverseStream`, `InvokeModel`, and `InvokeModelWithResponseStream`. It does not currently capture calls made through the `bedrock-mantle` endpoint.

## Module scope

This module is the shared Terraform source for Amazon Bedrock capabilities in an AWS account and region. It currently covers the whole `aws_bedrock_*` resource family. The remaining Bedrock surface belongs in this same module as further optional sections:

- **`aws_bedrockagent_*`** — agents, action groups, aliases, collaborators, knowledge bases, data sources, flows, and prompts. Knowledge bases and data sources also need an external vector store (OpenSearch Serverless, Aurora, or a third-party store), so they should take an existing store reference rather than provisioning one here.
- **`aws_bedrockagentcore_*`** — agent runtimes and endpoints, gateways and gateway targets, browsers, code interpreters, memory, evaluators, policies, and credential providers.

The long-term module surface should track the Bedrock resources exposed by the AWS Terraform provider. Each release must clearly distinguish implemented sections from provider capabilities that are still planned.

Follow the repository's ECS module pattern when extending it:

- Keep one Terraform source module at `ai/bedrock`.
- Put each Bedrock capability in its own `.tf` file and variable/output section.
- Model repeatable resources as keyed maps and create them with `for_each`.
- Keep object-typed variables flat enough to mirror the Ravion form shape, so the definition can pass inputs straight through instead of reshaping them.
- Add Ravion definition variants over the same source module only when a simpler use-case-specific experience is useful.
- Keep account- and region-wide singleton resources, such as model invocation logging, unique within the module.

## Usage

```hcl
module "bedrock" {
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.2.0"

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
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.2.0"

  name   = "ai-prod"
  region = "us-west-2"

  text_data_delivery_enabled      = true
  image_data_delivery_enabled     = true
  embedding_data_delivery_enabled = true
  video_data_delivery_enabled     = false
}
```

### Guardrails

```hcl
module "bedrock" {
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.2.0"

  name   = "ravion-prod"
  region = "us-west-2"

  guardrails = {
    support-assistant = {
      description              = "Guardrail for the customer support assistant"
      version_creation_enabled = true
      version_description      = "v1 - initial policy set"

      content_filters = [
        { type = "HATE", input_strength = "HIGH", output_strength = "HIGH" },
        { type = "VIOLENCE", input_strength = "HIGH", output_strength = "HIGH" },
        { type = "PROMPT_ATTACK", input_strength = "HIGH", output_strength = "NONE" },
      ]

      denied_topics = [{
        name       = "investment-advice"
        definition = "Any recommendation to buy or sell a specific security."
        examples   = ["Should I buy this stock?"]
      }]

      pii_entities = [
        { type = "EMAIL", action = "ANONYMIZE" },
        { type = "US_SOCIAL_SECURITY_NUMBER", action = "BLOCK" },
      ]

      grounding_filters = [
        { type = "GROUNDING", threshold = 0.75 },
        { type = "RELEVANCE", threshold = 0.5 },
      ]
    }
  }
}
```

### Inference profiles, provisioned throughput, and model access

```hcl
module "bedrock" {
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.2.0"

  name   = "ravion-prod"
  region = "us-west-2"

  # Track invocation cost and usage per application.
  inference_profiles = {
    chat = {
      description = "Chat workload"
      copy_from   = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
    }
  }

  # Reserve dedicated capacity. Omit commitment_duration to bill on demand.
  provisioned_model_throughputs = {
    chat = {
      model_arn   = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
      model_units = 2
    }
  }

  # Grant the account access to a model in this region.
  foundation_model_agreements = {
    claude = {
      model_id = "anthropic.claude-sonnet-4-20250514-v1:0"
    }
  }

  model_access_use_case_form_data = jsonencode({
    companyName   = "Example Inc"
    intendedUsers = "Internal support agents"
    useCases      = "Summarizing internal support tickets"
  })
}
```

### Custom model customization job

```hcl
module "bedrock" {
  source = "git::https://github.com/flightcontrolhq/modules.git//ai/bedrock?ref=rvn-bedrock@0.2.0"

  name   = "ravion-prod"
  region = "us-west-2"

  custom_models = {
    support = {
      base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
      role_arn              = aws_iam_role.bedrock_customization.arn
      hyperparameters = {
        epochCount = "2"
      }
      training_data_s3_uri    = "s3://ravion-bedrock-training/support/train.jsonl"
      output_data_s3_uri      = "s3://ravion-bedrock-training/support/output/"
      validation_data_s3_uris = ["s3://ravion-bedrock-training/support/validate.jsonl"]
    }
  }
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
| guardrails | Map of guardrails, keyed by logical name | `map(object)` | `{}` | no |
| custom_models | Map of model customization jobs, keyed by logical name | `map(object)` | `{}` | no |
| inference_profiles | Map of application inference profiles, keyed by logical name | `map(object)` | `{}` | no |
| provisioned_model_throughputs | Map of provisioned throughput reservations, keyed by logical name | `map(object)` | `{}` | no |
| foundation_model_agreements | Map of foundation model agreements to accept, keyed by logical name | `map(object)` | `{}` | no |
| model_access_use_case_form_data | JSON use case form submitted for models that require approval | `string` | `null` | no |
| tags | Additional tags for resources created by the module | `map(string)` | `{}` | no |

### Guardrail entry

| Field | Description | Type | Default |
|-------|-------------|------|---------|
| name | Guardrail name | `string` | map key |
| description | Guardrail description | `string` | `null` |
| blocked_input_messaging | Message returned when an input is blocked | `string` | `"Sorry, I am unable to respond to that request."` |
| blocked_outputs_messaging | Message returned when an output is blocked | `string` | `"Sorry, I am unable to respond to that request."` |
| kms_key_arn | Customer-managed KMS key for the guardrail | `string` | `null` |
| content_filters | Harmful content categories: `type`, `input_strength`, `output_strength`, optional actions/enabled/modalities | `list(object)` | `[]` |
| content_filter_tier | `CLASSIC` or `STANDARD` | `string` | `null` |
| denied_topics | Refused topics: `name`, `definition`, `examples` | `list(object)` | `[]` |
| denied_topic_tier | `CLASSIC` or `STANDARD` | `string` | `null` |
| denied_words | Blocked words: `text`, optional actions/enabled | `list(object)` | `[]` |
| managed_word_lists | AWS-managed word lists: `type` | `list(object)` | `[]` |
| pii_entities | PII handling: `type`, `action`, optional actions/enabled | `list(object)` | `[]` |
| regex_filters | Custom patterns: `name`, `pattern`, `action`, `description` | `list(object)` | `[]` |
| grounding_filters | Grounding checks: `type`, `threshold` | `list(object)` | `[]` |
| cross_region_guardrail_profile_identifier | Guardrail profile ARN for cross-region evaluation | `string` | `null` |
| version_creation_enabled | Publish an immutable version | `bool` | `false` |
| version_description | Published version description | `string` | `null` |
| version_skip_destroy | Retain the published version on destroy | `bool` | `false` |
| tags | Additional tags for this guardrail | `map(string)` | `null` |

### Custom model entry

| Field | Description | Type | Default |
|-------|-------------|------|---------|
| custom_model_name | Resulting custom model name | `string` | `<name>-<key>` |
| job_name | Customization job name | `string` | `<name>-<key>` |
| base_model_identifier | Base model ID or ARN | `string` | required |
| role_arn | IAM role Bedrock assumes for the job | `string` | required |
| customization_type | `FINE_TUNING`, `CONTINUED_PRE_TRAINING`, `DISTILLATION`, or `IMPORTED` | `string` | `"FINE_TUNING"` |
| hyperparameters | Training hyperparameters | `map(string)` | required |
| training_data_s3_uri | Training dataset URI | `string` | required |
| output_data_s3_uri | Job output URI | `string` | required |
| validation_data_s3_uris | Validation dataset URIs | `list(string)` | `[]` |
| vpc_subnet_ids | Subnets the job runs in | `set(string)` | `[]` |
| vpc_security_group_ids | Security groups for the job | `set(string)` | `[]` |
| kms_key_id | Customer-managed KMS key for the custom model | `string` | `null` |
| tags | Additional tags for this custom model | `map(string)` | `null` |

### Inference profile, throughput, and agreement entries

| Variable | Fields |
|----------|--------|
| inference_profiles | `name` (defaults to `<name>-<key>`), `description`, `copy_from` (required), `tags` |
| provisioned_model_throughputs | `provisioned_model_name` (defaults to `<name>-<key>`), `model_arn` (required), `model_units` (required), `commitment_duration`, `tags` |
| foundation_model_agreements | `model_id` (required), `offer_token`, `offer_type` (`PUBLIC` or `ALL`, default `PUBLIC`) |

## Outputs

| Name | Description |
|------|-------------|
| model_invocation_logging_configuration_id | Region identifying the Bedrock model invocation logging configuration; null if disabled |
| model_invocation_log_group_name | CloudWatch log group name; null if disabled |
| model_invocation_log_group_arn | CloudWatch log group ARN; null if disabled |
| model_invocation_logging_role_arn | IAM role ARN used by Bedrock for log delivery; null if disabled |
| guardrail_ids | Map of guardrail key to guardrail ID |
| guardrail_arns | Map of guardrail key to guardrail ARN |
| guardrail_versions | Map of guardrail key to the draft version reported by the guardrail |
| guardrail_published_versions | Map of guardrail key to published immutable version number |
| custom_model_arns | Map of custom model key to custom model ARN |
| custom_model_job_arns | Map of custom model key to customization job ARN |
| custom_model_names | Map of custom model key to custom model name |
| inference_profile_ids | Map of inference profile key to profile ID |
| inference_profile_arns | Map of inference profile key to profile ARN |
| provisioned_model_throughput_arns | Map of reservation key to provisioned model ARN |
| foundation_model_agreement_model_ids | Map of agreement key to accepted model ID |
| aws_account_id | AWS account ID where Bedrock is configured |
| region | AWS region where Bedrock is configured |

## KMS key policy

When `log_group_kms_key_arn` is set, the KMS key policy must allow the regional CloudWatch Logs service principal to use the key. See the AWS CloudWatch Logs documentation for the required key policy.

## Learn more

- [Amazon Bedrock model invocation logging](https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html)
- [Terraform AWS provider resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_model_invocation_logging_configuration)
