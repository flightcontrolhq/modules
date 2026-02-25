# AWS Lambda Module

This module creates an AWS Lambda function with broad runtime configuration support, optional IAM role creation, CloudWatch log group management, and optional integrations such as permissions, event source mappings, aliases, and function URL.

## Features

- Supports both `Zip` and `Image` package types
- Supports standard Lambda and Lambda@Edge validation mode
- Optional IAM role creation or use of an existing role
- Optional CloudWatch log group creation with retention and KMS encryption
- Optional invoke permissions (`aws_lambda_permission`)
- Optional event source mappings (`aws_lambda_event_source_mapping`)
- Optional aliases with weighted routing (`aws_lambda_alias`)
- Optional function URL with CORS configuration (`aws_lambda_function_url`)
- Consistent tagging with module defaults

## Usage

### Basic ZIP Function

```hcl
module "lambda" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name        = "orders-handler"
  package_type = "Zip"
  runtime     = "nodejs20.x"
  handler     = "index.handler"
  s3_bucket   = "my-lambda-artifacts"
  s3_key      = "orders-handler.zip"
}
```

### Container Image Function

```hcl
module "lambda_image" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name         = "image-fn"
  package_type = "Image"
  image_uri    = "123456789012.dkr.ecr.us-east-1.amazonaws.com/image-fn:latest"
  timeout      = 30
  memory_size  = 512
}
```

### Lambda@Edge-Compatible Function

```hcl
provider "aws" {
  region = "us-east-1"
}

module "edge_lambda" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name              = "edge-rewrite"
  is_lambda_at_edge = true

  package_type = "Zip"
  publish      = true
  runtime      = "nodejs20.x"
  handler      = "index.handler"
  s3_bucket    = "my-lambda-artifacts"
  s3_key       = "edge-rewrite.zip"

  # Lambda@Edge constraints enforced by module validation:
  # - x86_64 architecture
  # - no env vars / VPC / layers / DLQ / EFS
  # - timeout <= 30, memory <= 3008
}
```

### With Integrations

```hcl
module "lambda_with_integrations" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name         = "processor"
  package_type = "Zip"
  runtime      = "python3.12"
  handler      = "handler.main"
  s3_bucket    = "my-lambda-artifacts"
  s3_key       = "processor.zip"

  permissions = [
    {
      principal  = "events.amazonaws.com"
      source_arn = "arn:aws:events:us-east-1:123456789012:rule/my-rule"
    }
  ]

  event_source_mappings = [
    {
      event_source_arn = "arn:aws:sqs:us-east-1:123456789012:jobs-queue"
      batch_size       = 10
    }
  ]

  aliases = {
    live = {
      function_version = "1"
    }
  }

  function_url_enabled   = true
  function_url_auth_type = "AWS_IAM"
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the Lambda function | `string` | n/a | yes |
| description | Description of the Lambda function | `string` | `null` | no |
| tags | Tags to assign to all resources | `map(string)` | `{}` | no |
| package_type | Package type (`Zip` or `Image`) | `string` | `"Zip"` | no |
| architectures | Lambda architectures | `list(string)` | `["x86_64"]` | no |
| publish | Publish a version on update | `bool` | `false` | no |
| handler | Function handler (Zip only) | `string` | `null` | no |
| runtime | Function runtime (Zip only) | `string` | `null` | no |
| filename | Local ZIP package path | `string` | `null` | no |
| source_code_hash | Base64 SHA256 of package | `string` | `null` | no |
| s3_bucket | S3 bucket for package | `string` | `null` | no |
| s3_key | S3 key for package | `string` | `null` | no |
| s3_object_version | S3 object version for package | `string` | `null` | no |
| image_uri | Image URI (Image only) | `string` | `null` | no |
| image_config | Image config override object | `object` | `null` | no |
| memory_size | Memory in MB | `number` | `128` | no |
| timeout | Timeout in seconds | `number` | `3` | no |
| kms_key_arn | KMS key ARN for environment encryption | `string` | `null` | no |
| layers | Lambda layer ARNs | `list(string)` | `[]` | no |
| reserved_concurrent_executions | Reserved concurrency | `number` | `null` | no |
| ephemeral_storage_size | `/tmp` size in MB | `number` | `512` | no |
| tracing_mode | X-Ray tracing mode | `string` | `"PassThrough"` | no |
| environment_variables | Environment variables map | `map(string)` | `{}` | no |
| vpc_config | VPC config object | `object` | `null` | no |
| dead_letter_target_arn | SQS/SNS dead letter target ARN | `string` | `null` | no |
| file_system_configs | EFS mount configs | `list(object)` | `[]` | no |
| snap_start_apply_on | SnapStart mode (`PublishedVersions`) | `string` | `null` | no |
| code_signing_config_arn | Code signing config ARN | `string` | `null` | no |
| create_role | Create IAM role | `bool` | `true` | no |
| role_arn | Existing IAM role ARN | `string` | `null` | no |
| role_name | IAM role name override | `string` | `null` | no |
| role_path | IAM role path | `string` | `"/"` | no |
| role_permissions_boundary | IAM permissions boundary ARN | `string` | `null` | no |
| attach_basic_execution_policy | Attach AWS basic execution policy | `bool` | `true` | no |
| attach_vpc_execution_policy | Attach AWS VPC execution policy when vpc_config is set | `bool` | `true` | no |
| role_managed_policy_arns | Additional managed policy ARNs | `list(string)` | `[]` | no |
| role_inline_policies | Inline IAM policies map (`name => json`) | `map(string)` | `{}` | no |
| create_log_group | Create CloudWatch log group | `bool` | `true` | no |
| log_group_name | Custom log group name | `string` | `null` | no |
| log_retention_days | Log retention in days | `number` | `30` | no |
| log_kms_key_id | KMS key for log group | `string` | `null` | no |
| permissions | Permission statements | `list(object)` | `[]` | no |
| event_source_mappings | Event source mappings | `list(object)` | `[]` | no |
| aliases | Lambda aliases keyed by alias name | `map(object)` | `{}` | no |
| function_url_enabled | Create function URL | `bool` | `false` | no |
| function_url_auth_type | Function URL auth type (`NONE` or `AWS_IAM`) | `string` | `"AWS_IAM"` | no |
| function_url_invoke_mode | Function URL invoke mode (`BUFFERED` or `RESPONSE_STREAM`) | `string` | `"BUFFERED"` | no |
| function_url_cors | Function URL CORS object | `object` | `null` | no |
| is_lambda_at_edge | Enable Lambda@Edge compatibility validations | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| function_name | Lambda function name |
| function_arn | Lambda function ARN |
| function_invoke_arn | Lambda function invoke ARN |
| function_qualified_arn | Lambda function qualified ARN |
| function_version | Latest function version |
| function_last_modified | Function last modified timestamp |
| role_arn | IAM role ARN used by function |
| log_group_name | CloudWatch log group name |
| log_group_arn | CloudWatch log group ARN (if created) |
| permission_statement_ids | Permission statement IDs by item index |
| event_source_mapping_ids | Event source mapping UUIDs by item index |
| alias_arns | Alias ARNs by alias name |
| function_url | Function URL when enabled |

## Notes

- Lambda@Edge deployments must be created in `us-east-1`.
- The module enforces key Lambda@Edge constraints when `is_lambda_at_edge = true`.
- For `Zip` package type, provide either `filename` or (`s3_bucket` + `s3_key`).
- For `Image` package type, provide `image_uri`.
