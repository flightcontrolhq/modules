# AWS S3 Bucket

Creates an enterprise-grade S3 bucket with security best practices including public access blocking, server-side encryption (SSE-S3 or SSE-KMS), versioning, lifecycle rules, and configurable bucket policies.

This module is designed for both standalone use and composition within other modules, providing a reusable foundation for S3 storage needs such as access logs, flow logs, application data, and more.

## Usage

### Basic Bucket

```hcl
module "s3" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name = "my-application-bucket"

  tags = {
    Environment = "production"
  }
}
```

### Bucket with KMS Encryption

```hcl
module "s3" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name       = "my-encrypted-bucket"
  kms_key_id = aws_kms_key.s3.arn

  tags = {
    Environment = "production"
  }
}
```

### Bucket with Versioning

```hcl
module "s3" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name               = "my-versioned-bucket"
  versioning_enabled = true

  tags = {
    Environment = "production"
  }
}
```

### Bucket with Lifecycle Rules

```hcl
module "s3" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name               = "my-lifecycle-bucket"
  versioning_enabled = true

  lifecycle_rules = [
    {
      id     = "expire-old-objects"
      prefix = "logs/"
      expiration = {
        days = 90
      }
    },
    {
      id     = "archive-to-glacier"
      prefix = "backups/"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    },
    {
      id = "cleanup-incomplete-uploads"
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### ALB Access Logs Bucket

```hcl
module "alb_logs" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name             = "my-alb-access-logs"
  force_destroy    = true
  policy_templates = ["alb_access_logs", "deny_insecure_transport"]

  lifecycle_rules = [
    {
      id = "expire-logs"
      expiration = {
        days = 90
      }
    }
  ]

  tags = {
    Purpose = "ALB Access Logs"
  }
}

# Use with ALB module
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name                   = "main"
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.public_subnet_ids
  enable_access_logs     = true
  access_logs_bucket_arn = module.alb_logs.bucket_arn
}
```

### VPC Flow Logs Bucket

```hcl
module "flow_logs" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name             = "my-vpc-flow-logs"
  force_destroy    = true
  policy_templates = ["vpc_flow_logs", "deny_insecure_transport"]

  lifecycle_rules = [
    {
      id = "expire-logs"
      expiration = {
        days = 30
      }
    }
  ]

  tags = {
    Purpose = "VPC Flow Logs"
  }
}
```

### NLB Access Logs Bucket

```hcl
module "nlb_logs" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name             = "my-nlb-access-logs"
  force_destroy    = true
  policy_templates = ["nlb_access_logs", "deny_insecure_transport"]

  lifecycle_rules = [
    {
      id = "expire-logs"
      expiration = {
        days = 90
      }
    }
  ]

  tags = {
    Purpose = "NLB Access Logs"
  }
}
```

### Bucket with Custom Policy

```hcl
module "s3" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name = "my-custom-policy-bucket"

  # Combine templates with custom policy
  policy_templates = ["deny_insecure_transport"]

  custom_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::my-custom-policy-bucket/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::123456789012:distribution/EXAMPLE"
          }
        }
      }
    ]
  })

  tags = {
    Environment = "production"
  }
}
```

### Full Configuration Example

```hcl
module "s3" {
  source = "git::https://github.com/flightcontrolhq/modules.git//storage/s3?ref=v1.0.0"

  name          = "my-full-config-bucket"
  force_destroy = false

  # Encryption
  kms_key_id         = aws_kms_key.s3.arn
  bucket_key_enabled = true

  # Versioning
  versioning_enabled = true

  # Public access block (all enabled by default)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Lifecycle rules
  lifecycle_rules = [
    {
      id = "archive-and-expire"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 365
      }
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    }
  ]

  # Policies
  policy_templates = ["deny_insecure_transport"]

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

| Name                      | Description                                                                                                                       | Type                                             | Default | Required |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ------- | -------- |
| name                      | The name of the S3 bucket. Must be globally unique and follow AWS S3 bucket naming rules.                                         | `string`                                         | n/a     | yes      |
| tags                      | A map of tags to assign to resources. These tags will be merged with default module tags.                                         | `map(string)`                                    | `{}`    | no       |
| force_destroy             | Whether to force destroy the bucket even if it contains objects. Use with caution.                                                | `bool`                                           | `false` | no       |
| block_public_acls         | Whether Amazon S3 should block public ACLs for this bucket.                                                                       | `bool`                                           | `true`  | no       |
| block_public_policy       | Whether Amazon S3 should block public bucket policies for this bucket.                                                            | `bool`                                           | `true`  | no       |
| ignore_public_acls        | Whether Amazon S3 should ignore public ACLs for this bucket.                                                                      | `bool`                                           | `true`  | no       |
| restrict_public_buckets   | Whether Amazon S3 should restrict public bucket policies for this bucket.                                                         | `bool`                                           | `true`  | no       |
| kms_key_id                | The AWS KMS key ID or ARN to use for server-side encryption (SSE-KMS). If not specified, SSE-S3 (AES256) encryption is used.      | `string`                                         | `null`  | no       |
| bucket_key_enabled        | Whether to enable S3 Bucket Keys for SSE-KMS, which reduces KMS API costs. Only applicable when kms_key_id is provided.           | `bool`                                           | `true`  | no       |
| versioning_enabled        | Whether to enable versioning for the S3 bucket. When enabled, S3 keeps multiple versions of an object in the same bucket.         | `bool`                                           | `false` | no       |
| lifecycle_rules           | List of lifecycle rule configurations for the bucket. See [Lifecycle Rules](#lifecycle-rules) section below.                      | `list(object({...}))`                            | `[]`    | no       |
| policy_templates          | List of policy template names to apply. Available: `deny_insecure_transport`, `alb_access_logs`, `nlb_access_logs`, `vpc_flow_logs`. | `list(string)`                                   | `[]`    | no       |
| custom_policy             | Custom bucket policy JSON document. If provided alongside policy_templates, policies will be merged.                              | `string`                                         | `null`  | no       |

## Outputs

| Name                        | Description                                                                      |
| --------------------------- | -------------------------------------------------------------------------------- |
| bucket_id                   | The name of the S3 bucket.                                                       |
| bucket_arn                  | The ARN of the S3 bucket.                                                        |
| bucket_domain_name          | The bucket domain name (e.g., bucket-name.s3.amazonaws.com).                     |
| bucket_regional_domain_name | The bucket region-specific domain name (e.g., bucket-name.s3.us-east-1.amazonaws.com). |
| bucket_hosted_zone_id       | The Route 53 Hosted Zone ID for this bucket's region (for alias records).        |
| bucket_region               | The AWS region this bucket resides in.                                           |
| bucket_policy               | The policy document attached to the bucket (null if no policy).                  |
| versioning_enabled          | Whether versioning is enabled on the bucket.                                     |
| encryption_algorithm        | The server-side encryption algorithm used (AES256 or aws:kms).                   |
| kms_key_id                  | The KMS key ID used for encryption (null if using SSE-S3).                       |

## Lifecycle Rules

The `lifecycle_rules` variable accepts a list of objects with the following structure:

| Field                                | Description                                              | Type              | Required |
| ------------------------------------ | -------------------------------------------------------- | ----------------- | -------- |
| id                                   | Unique identifier for the rule                           | `string`          | yes      |
| enabled                              | Whether the rule is enabled                              | `bool`            | no       |
| prefix                               | Object key prefix to filter objects                      | `string`          | no       |
| tags                                 | Tags to filter objects                                   | `map(string)`     | no       |
| expiration                           | Settings for expiring current objects                    | `object`          | no       |
| noncurrent_version_expiration        | Settings for expiring noncurrent versions                | `object`          | no       |
| transitions                          | List of transitions to different storage classes         | `list(object)`    | no       |
| noncurrent_version_transitions       | Transitions for noncurrent versions                      | `list(object)`    | no       |
| abort_incomplete_multipart_upload_days | Days after which incomplete multipart uploads are aborted | `number`         | no       |

### Storage Classes for Transitions

Valid storage classes for transitions:
- `STANDARD_IA` - Standard-Infrequent Access
- `ONEZONE_IA` - One Zone-Infrequent Access
- `INTELLIGENT_TIERING` - Intelligent-Tiering
- `GLACIER` - Glacier Flexible Retrieval
- `GLACIER_IR` - Glacier Instant Retrieval
- `DEEP_ARCHIVE` - Glacier Deep Archive

## Policy Templates

The module includes pre-built bucket policy templates for common use cases:

| Template Name           | Description                                                       |
| ----------------------- | ----------------------------------------------------------------- |
| `deny_insecure_transport` | Denies requests that don't use HTTPS (enforces TLS).            |
| `alb_access_logs`       | Allows ALB to write access logs to the bucket.                    |
| `nlb_access_logs`       | Allows NLB to write access logs to the bucket.                    |
| `vpc_flow_logs`         | Allows VPC Flow Logs to write logs to the bucket.                 |

Multiple templates can be combined, and they can also be used alongside a custom policy. All policies are merged into a single bucket policy.

## Security Considerations

- **Public Access Blocked**: All four public access block settings are enabled by default.
- **Encryption**: Server-side encryption is always enabled. Uses SSE-S3 (AES256) by default, or SSE-KMS when a KMS key is provided.
- **HTTPS Enforcement**: Use the `deny_insecure_transport` policy template to enforce HTTPS-only access.
- **Bucket Keys**: When using SSE-KMS, S3 Bucket Keys are enabled by default to reduce KMS API costs.

## Notes

- Bucket names must be globally unique across all AWS accounts.
- Bucket names must be between 3-63 characters, contain only lowercase letters, numbers, hyphens, and periods.
- The `force_destroy` option should be used with caution in production environments.
- When using lifecycle rules with versioning, consider configuring `noncurrent_version_expiration` to manage storage costs.
