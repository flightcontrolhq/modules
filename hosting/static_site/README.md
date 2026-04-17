# Static Site Hosting

End-to-end composite module for hosting static sites on AWS using S3 + CloudFront. Composes [`storage/s3`](../../storage/s3), [`cdn/cloudfront`](../../cdn/cloudfront), and (optionally) [`compute/lambda`](../../compute/lambda).

This is a hosting solution, not a CDN primitive — it bundles an S3 hosting bucket, a private CloudFront distribution (with OAC), modern cache behaviors, an optional CloudFront Function for clean URLs, and an optional Lambda@Edge handler for FC-style preview environments and deployment versioning.

## Features

- **Three modes** selectable via a single `mode` variable (`spa`, `filesystem`, `filesystem_previews`)
- **Origin Access Control (OAC)** by default — no public buckets, no legacy OAI
- **SPA fallback** via CloudFront `custom_error_responses` (no Lambda needed)
- **CloudFront Function** for cheap path rewriting at every edge POP (`filesystem` mode)
- **Lambda@Edge handler** for filesystem-mode existence checks, deployment versioning, and preview environments (`filesystem_previews` mode)
- **CloudFront KeyValueStore** for `Host` -> deployment-prefix lookups at the edge
- **Multiple distributions** sharing one origin (e.g., a production domain group + staging domain group)
- **Cache strategy**: long-cache hashed assets via `CachingOptimized`, short/no-cache for `/index.html` to prevent stale shells after deploys
- **HTTP/2 + HTTP/3** by default
- **Optional WAFv2** integration
- **Optional access logging** (existing or module-created bucket)
- **Optional CI deploy role** with least-privilege `s3:Put*` + `cloudfront:CreateInvalidation`
- **Origin Shield** support
- **SSE-KMS** support on the hosting bucket

## Mode Matrix

| Mode | Edge compute | SPA fallback | Path rewriting | Deployment versioning | Preview environments | Use when |
|---|---|---|---|---|---|---|
| `spa` (default) | none | CloudFront error responses (403/404 -> `/index.html`) | none | client-side router | external | Single-page apps (React, Vue, Svelte, etc.) |
| `filesystem` | CloudFront Function | none | clean URLs (`/foo` -> `/foo/index.html`), trailing-slash | static origin header | external | Multi-page static sites (Astro, Hugo, MkDocs, plain HTML) |
| `filesystem_previews` | CloudFront Function + Lambda@Edge + optional KVS | conditional via `static_mode_header_value` | existence-based (`/foo` matches `/foo.html` or `/foo/index.html`), trailing-slash redirect, custom 404 | per-request via `x-fc-deployment-id` | host -> prefix mapped at the edge | Flightcontrol-style hosting with PR previews and atomic deploys |

## Architecture

```
                     +----------+
                     |  Viewer  |
                     +----+-----+
                          | HTTPS
                          v
              +-----------+------------+
              |  CloudFront            |
              |   - HTTP/2 + HTTP/3    |
              |   - WAF (optional)     |
              |   - Logging (optional) |
              +--+---------+------+----+
                 | viewer  |      | origin
                 | request |      | request
                 v         |      v
        +--------+-----+   |   +--+---------------+
        | CloudFront   |   |   | Lambda@Edge      |
        | Function     |   |   | (filesystem_     |
        | (filesystem  |   |   |  previews only)  |
        |  modes only) |   |   +--+---------------+
        +-----+--------+   |      |
              |            |      | SigV4
              | KVS lookup |      v
              v            |   +--+----------+
        +-----+---+        |   | S3 Hosting  |
        |   KVS   |        +-->| Bucket      |<---+ OAC SigV4
        +---------+            | (private)   |
                               +-------------+
```

## Quick Start

### SPA mode (React/Vue/etc.)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "my-marketing-site"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }
}

# Deploy from CI:
#   aws s3 sync ./dist s3://my-marketing-site/
#   aws cloudfront create-invalidation --distribution-id <id> --paths '/*'
```

### Filesystem mode (Astro/Hugo/MkDocs)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "my-docs-site"
  mode = "filesystem"

  distributions = {
    main = {
      aliases             = ["docs.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  long_cache_paths = ["/_astro/*", "/assets/*"]
}
```

### Filesystem + Previews (Flightcontrol parity)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "my-app"
  mode = "filesystem_previews"

  distributions = {
    main = {
      aliases             = ["app.example.com", "*.preview.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  static_mode_header_value   = "filesystem"
  deployment_id_header_value = "main"
  trailing_slash_enabled     = true

  create_key_value_store = true

  kvs_initial_data = {
    "pr-42.preview.example.com" = "versions/pr-42"
    "pr-87.preview.example.com" = "versions/pr-87"
  }
}

# Deploy a PR preview from CI:
#   aws s3 sync ./dist s3://my-app/versions/pr-42/
#   aws cloudfront-keyvaluestore put-key \
#     --kvs-arn $(tofu output -raw key_value_store_arn) \
#     --if-match $(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn ... --query ETag --output text) \
#     --key pr-42.preview.example.com \
#     --value versions/pr-42
```

### Multi-distribution (production + staging)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "my-app"

  distributions = {
    production = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/prod-cert"
    }
    staging = {
      aliases             = ["staging.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/staging-cert"
    }
  }
}
```

### With CI Deploy Role (GitHub OIDC)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "my-app"

  distributions = { main = {} }

  create_deploy_role = true
  deploy_role_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:my-org/my-repo:ref:refs/heads/main" }
      }
    }]
  })
}
```

## Provider configuration

This module always requires two AWS provider configurations:

```hcl
provider "aws" {
  region = "us-west-2"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

The `us_east_1` alias is required by Lambda@Edge (only used in `filesystem_previews` mode but declared unconditionally so the same module call works across modes). All other resources go to the default provider's region.

ACM certificates for CloudFront aliases must also live in `us-east-1` regardless of the rest of your stack. Provision them with [`security/acm_certificate`](../../security/acm_certificate) using the `us_east_1` alias and pass the ARN to `distributions[].acm_certificate_arn`.

## Comparison vs the legacy Flightcontrol CloudFormation stack

| Concern | Legacy `create-static-stack.json` | `hosting/static_site` (this module) |
|---|---|---|
| Origin access | `CloudFrontOriginAccessIdentity` (OAI) | Origin Access Control (OAC) — supports SSE-KMS, SigV4 |
| SPA fallback | Lambda@Edge `headObject` round trip | CloudFront `custom_error_responses` (zero compute, no S3 RPS) |
| Trivial path rewriting | Lambda@Edge | CloudFront Function (cheaper, runs at all POPs) |
| Build pipeline | CodeBuild bundled in the stack | Out of scope — driven by CI; optional `create_deploy_role` |
| Buckets created | Hosting + Build | Hosting only |
| HTTP/3 | Off (HTTP/2 only) | On by default |
| Preview host -> prefix lookup | Lambda@Edge runtime check on Referer | CloudFront Function + KeyValueStore at the edge |
| Lambda@Edge handler | Always created | Only in `filesystem_previews` mode |
| Lambda@Edge IAM | `AmazonS3ReadOnlyAccess` managed policy | Inline policy scoped to `${hosting_bucket_arn}/*` |

For migration from the FC stack, deploy this module side-by-side, copy objects via `aws s3 sync s3://hosting-old/main/ s3://hosting-new/`, swap your DNS record (or update the CloudFront alias), then delete the legacy stack.

## Lambda@Edge build

The bundled handler under `edge/handler/` declares its dependencies in `package.json`. The first apply runs `npm install --omit=dev` automatically via a `null_resource` provisioner (you need `npm` on the machine running `tofu apply`). To use your own handler instead, set `lambda_source_dir` to a directory containing `index.js` (and `node_modules/` if needed); the bundled `npm install` is skipped.

## Cache strategy

| Path pattern | Cache policy | Why |
|---|---|---|
| (default) | AWS-managed `CachingOptimized` (1y TTL, no headers/cookies/QS) | Hashed assets are immutable |
| `/index.html` | AWS-managed `CachingDisabled` | Prevents stale shells; HTML must be revalidated every deploy |
| `/assets/*`, `/_next/static/*`, etc. | `CachingOptimized` | Explicit echo of the default for clarity (configure via `long_cache_paths`) |

Override per-path patterns via `no_cache_paths` and `long_cache_paths`. Override the cache policy entirely via `cache_policy_id`, `origin_request_policy_id`, and `response_headers_policy_id`.

## Requirements

| Name | Version |
|---|---|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |
| archive | >= 2.4.0 |

External tools used at apply time (only when `mode = "filesystem_previews"` and `lambda_source_dir` is unset):

- `npm` (Node.js 18+) — bundled with most CI images and developer machines

## Inputs

### Required

| Name | Description | Type |
|---|---|---|
| name | Name prefix for all resources; also used as the hosting bucket name (must be globally unique). | `string` |

### General

| Name | Description | Type | Default |
|---|---|---|---|
| mode | Hosting mode: `spa`, `filesystem`, `filesystem_previews`. | `string` | `"spa"` |
| distributions | Map of CloudFront distributions sharing the same origin. | `map(object)` | `{ main = {} }` |
| tags | Tags to apply to all resources. | `map(string)` | `{}` |

### Distribution

| Name | Description | Type | Default |
|---|---|---|---|
| price_class | CloudFront price class. | `string` | `"PriceClass_100"` |
| minimum_protocol_version | Minimum TLS version when using a custom ACM cert. | `string` | `"TLSv1.2_2021"` |
| geo_restriction_type | `none`, `whitelist`, `blacklist`. | `string` | `"none"` |
| geo_restriction_locations | ISO-3166-1-alpha-2 country codes. | `list(string)` | `[]` |
| web_acl_id | WAFv2 (global scope) Web ACL ARN. | `string` | `null` |
| wait_for_deployment | Wait for distributions to deploy on apply. | `bool` | `true` |

### Hosting Bucket

| Name | Description | Type | Default |
|---|---|---|---|
| bucket_versioning | Enable S3 versioning on the hosting bucket. | `bool` | `true` |
| bucket_force_destroy | Allow destroy of a non-empty bucket. | `bool` | `false` |
| bucket_lifecycle_rules | Lifecycle rules. | `list(object)` | expire noncurrent after 30d, abort multipart after 7d |
| kms_key_arn | SSE-KMS key ARN; null = SSE-S3 (AES256). | `string` | `null` |

### Origin

| Name | Description | Type | Default |
|---|---|---|---|
| origin_shield_region | Enable Origin Shield in this region. | `string` | `null` |
| origin_path | Path prefix prepended to origin requests. | `string` | `null` |
| additional_origin_headers | Extra custom headers sent to S3. | `list(object({name, value}))` | `[]` |

### Cache Behavior

| Name | Description | Type | Default |
|---|---|---|---|
| cache_policy_id | Default cache policy ID. | `string` | AWS-managed CachingOptimized |
| origin_request_policy_id | Origin request policy ID. | `string` | AWS-managed CORS-S3Origin |
| response_headers_policy_id | Response headers policy ID. | `string` | `null` |
| no_cache_paths | Path patterns served with CachingDisabled. | `list(string)` | `["/index.html"]` |
| long_cache_paths | Path patterns explicitly served with the default long-cache policy. | `list(string)` | `[]` |
| default_root_object | Object returned for `/`. | `string` | `"index.html"` |
| spa_error_caching_min_ttl | TTL for the SPA fallback response. Only used in `spa` mode. | `number` | `10` |

### Logging

| Name | Description | Type | Default |
|---|---|---|---|
| enable_logging | Enable CloudFront access logging. | `bool` | `false` |
| create_logging_bucket | Create a new S3 bucket for logs. | `bool` | `false` |
| logging_bucket_domain_name | Existing logging bucket domain name. | `string` | `null` |
| logging_prefix | Base prefix for log files. | `string` | `""` |
| logging_retention_days | Days to retain logs in the created bucket. | `number` | `90` |

### Lambda@Edge (`filesystem_previews` mode)

| Name | Description | Type | Default |
|---|---|---|---|
| lambda_source_dir | Override directory for the Lambda@Edge handler. | `string` | `null` (use bundled handler) |
| lambda_memory_size | Lambda@Edge memory (MB). | `number` | `256` |
| lambda_timeout | Lambda@Edge timeout (seconds, max 30). | `number` | `5` |
| lambda_runtime | Node.js runtime. | `string` | `"nodejs20.x"` |
| lambda_log_retention_days | CloudWatch log retention. | `number` | `30` |
| static_mode_header_value | `spa` or `filesystem`. | `string` | `"spa"` |
| deployment_id_header_value | Default deployment prefix when KVS does not match. | `string` | `"main"` |
| preview_url_header_value | Optional value for the X-FC-PREVIEW-URL origin header. | `string` | `""` |
| trailing_slash_enabled | Enable 302 redirects to add trailing slashes. | `bool` | `false` |

### CloudFront KeyValueStore (`filesystem_previews` mode)

| Name | Description | Type | Default |
|---|---|---|---|
| create_key_value_store | Create a CloudFront KVS. | `bool` | `false` |
| kvs_initial_data | Map of host -> deployment-prefix used as the initial seed. | `map(string)` | `{}` |

### Deploy Role

| Name | Description | Type | Default |
|---|---|---|---|
| create_deploy_role | Create an IAM role for CI to assume. | `bool` | `false` |
| deploy_role_trust_policy | Trust policy JSON. Required when `create_deploy_role = true`. | `string` | `null` |
| deploy_role_name | Override role name. | `string` | `"<name>-deploy"` |

## Outputs

| Name | Description |
|---|---|
| hosting_bucket_id | Name of the S3 hosting bucket. |
| hosting_bucket_arn | ARN of the S3 hosting bucket. |
| hosting_bucket_regional_domain_name | Regional domain name of the hosting bucket. |
| hosting_bucket_region | AWS region of the hosting bucket. |
| distribution_ids | Map of distribution key -> CloudFront distribution ID. |
| distribution_arns | Map of distribution key -> distribution ARN. |
| distribution_domain_names | Map of distribution key -> CloudFront domain name. |
| distribution_hosted_zone_ids | Map of distribution key -> Route53 zone ID for alias records. |
| cloudfront_function_arn | ARN of the CloudFront Function (null in `spa` mode). |
| lambda_edge_function_arn | Unqualified Lambda@Edge ARN (null unless `filesystem_previews`). |
| lambda_edge_qualified_arn | Versioned Lambda@Edge ARN used in CloudFront associations. |
| lambda_edge_role_arn | IAM role ARN attached to the Lambda@Edge function. |
| key_value_store_arn | ARN of the CloudFront KVS (null unless created). |
| key_value_store_id | ID of the CloudFront KVS. |
| deploy_role_arn | ARN of the deploy role (null unless created). |
| deploy_role_name | Name of the deploy role. |
| invalidation_commands | Map of distribution key -> ready-to-run `aws cloudfront create-invalidation` command. |

## Security Considerations

- Hosting bucket has all four S3 public access block settings enabled by default (inherited from `storage/s3`)
- CloudFront uses OAC, not OAI — supports SSE-KMS and Object Lambda
- Bucket policy grants `s3:GetObject` only to `cloudfront.amazonaws.com` scoped to the specific distribution ARNs created by this module (defense in depth)
- In `filesystem_previews` mode, the Lambda@Edge role gets an inline policy scoped to `${hosting_bucket_arn}/*` only (not the AWS-managed `AmazonS3ReadOnlyAccess` policy, which grants account-wide read)
- Optional deploy role uses a fully user-supplied trust policy — no implicit cross-account trust
- TLS 1.2+ enforced on the viewer side (`minimum_protocol_version` defaults to `TLSv1.2_2021`)
- HTTP -> HTTPS redirect is the default viewer protocol policy

## Notes

- **Build is your job**: this module does not run a build step. Use any CI to produce a `dist/` directory and `aws s3 sync` it to the hosting bucket.
- **First request is slow**: CloudFront distributions take 5-15 minutes to deploy globally. `wait_for_deployment = true` (default) blocks `tofu apply` until ready; set to `false` for faster iteration.
- **KVS updates**: only the initial seed is managed via Terraform. Subsequent additions/deletions should be made via `aws cloudfront-keyvaluestore put-key`/`delete-key` from CI to avoid Terraform state churn for ephemeral previews.
- **Lambda@Edge replication**: function changes take 5-10 minutes to propagate to all regional edge caches. Plan deploys accordingly.
- **Route53 records**: create externally with [`networking/route53`](../../networking/route53) using the `distribution_domain_names` and `distribution_hosted_zone_ids` outputs.
- **ACM certificates**: create externally with [`security/acm_certificate`](../../security/acm_certificate) using the `us_east_1` provider alias.
