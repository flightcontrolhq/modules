# Static Site Hosting

End-to-end composite module for hosting static sites on AWS using S3 + CloudFront. Composes [`storage/s3`](../../storage/s3) and [`cdn/cloudfront`](../../cdn/cloudfront).

Every deployment is **versioned**. A CloudFront KeyValueStore holds a `host -> version` map; a single CloudFront Function rewrites every viewer request to `/<version>/...` before the cache lookup. Promoting or rolling back a build is one `put-key` call against the KVS.

## Features

- **Versioned-by-default**: every deploy lands at `s3://<bucket>/<version>/`, the KVS `active` key points at the live one.
- **Instant rollback**: flip `active` (or any per-host KVS entry) — KVS reads at the edge propagate within seconds.
- **No CloudFront invalidations needed**: the rewriter changes the rewritten URI, which is part of the cache key, so each promotion is automatically a fresh cache key.
- **Two routing styles**: `spa` (every non-asset path serves `<version>/index.html` for client-side routers) and `filesystem` (clean URLs, `/foo` → `<version>/foo/index.html`).
- **Per-host overrides**: pin staging to a specific version, run PR previews on `pr-*.preview.example.com` subdomains, gradual cutovers — all via KVS keys.
- **Origin Access Control (OAC)** by default — no public buckets, no legacy OAI.
- **Multiple distributions** sharing one origin (e.g., a production domain group + staging domain group).
- **HTTP/2 + HTTP/3** by default.
- **Optional WAFv2** integration.
- **Optional access logging** (existing or module-created bucket).
- **Optional CI deploy role** with least-privilege `s3:Put*` + KVS `PutKey`/`DeleteKey` + `cloudfront:CreateInvalidation`.
- **Origin Shield** support.
- **SSE-KMS** support on the hosting bucket.

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
         +-----------+------------+
                     | viewer-request
                     v
         +-----------+------------+        +-----+
         | CloudFront Function    |<------>| KVS |
         |   1. host -> version   |        +-----+
         |   2. rewrite URI:      |
         |      /foo -> /<v>/...  |
         +-----------+------------+
                     | (rewritten URI = cache key)
                     v
         +-----------+------------+
         | S3 Hosting Bucket      |
         | (private, OAC SigV4)   |
         +------------------------+
```

## Quick Start

### SPA (React/Vue/TanStack Router/etc.)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  long_cache_paths = ["/assets/*"]
}
```

### Filesystem (Astro/Hugo/MkDocs)

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name    = "my-docs"
  routing = "filesystem"

  distributions = {
    main = {
      aliases             = ["docs.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }
}
```

### With deploy role + per-host pinning

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com", "staging.example.com", "*.preview.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  # Pin staging to a known-good version while prod tracks 'active'.
  kvs_initial_data = {
    "staging.example.com" = "v_staging"
  }

  create_deploy_role = true
  deploy_role_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:my-org/my-repo:*" }
      }
    }]
  })
}
```

## Deploy and rollback

A new build is two steps from CI: upload, then flip.

```bash
VERSION="v$(git rev-parse --short HEAD)"

# 1. Upload the build to its own prefix (idempotent — re-runnable, no live impact)
aws s3 sync ./dist s3://${HOSTING_BUCKET}/${VERSION}/ --delete

# 2. Promote: point 'active' at the new version
KVS_ARN=$(tofu output -raw key_value_store_arn)
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key \
  --kvs-arn $KVS_ARN --if-match $ETAG \
  --key active --value $VERSION
```

Rollback is the same `put-key` call with the previous version. `outputs.set_active_version_command` returns the snippet pre-filled with the KVS ARN.

### PR previews

```bash
# Build for the PR's preview host
aws s3 sync ./dist s3://${HOSTING_BUCKET}/v_pr-42/ --delete

# Map the preview hostname to that version
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key \
  --kvs-arn $KVS_ARN --if-match $ETAG \
  --key pr-42.preview.example.com --value v_pr-42

# Tear down on PR close
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore delete-key \
  --kvs-arn $KVS_ARN --if-match $ETAG \
  --key pr-42.preview.example.com
```

The deploy role created when `create_deploy_role = true` has exactly the S3 + KVS permissions to do all of this.

## How the rewriter resolves a version

For each viewer request, the CloudFront Function does:

1. Look up `host` in the KVS → if hit, that version wins.
2. Look up `active` in the KVS → that's the production default.
3. Fall back to `default_version` (apply-time constant, defaults to `"main"`) → makes the very first deploy work before any KVS edits.

It then rewrites the URI by routing style:

| Routing | `/` | `/foo.js` | `/foo` or `/foo/` |
|---|---|---|---|
| `spa` | `/<v>/index.html` | `/<v>/foo.js` | `/<v>/index.html` |
| `filesystem` | `/<v>/index.html` | `/<v>/foo.js` | `/<v>/foo/index.html` |

Because CloudFront's cache key incorporates the rewritten URI, two different versions never collide in cache.

## Provider configuration

```hcl
provider "aws" {
  region = "us-west-2"
}
```

Only the default `aws` provider is required. ACM certificates for CloudFront aliases must still live in `us-east-1` regardless of the rest of your stack — provision them with [`security/acm_certificate`](../../security/acm_certificate) using a `us_east_1` provider alias in your root module and pass the ARN to `distributions[].acm_certificate_arn`.

## Cache strategy

| Path pattern | Cache policy | Why |
|---|---|---|
| (default) | AWS-managed `CachingOptimized` (1y TTL, no headers/cookies/QS) | Hashed assets are immutable; HTML files at `/<v>/index.html` are unique per version. |
| `long_cache_paths` | Same `CachingOptimized` | Explicit echo for documentation/clarity (e.g. `/_astro/*`, `/assets/*`). |
| `no_cache_paths` | AWS-managed `CachingDisabled` | Optional escape hatch — versioning makes per-path cache busting unnecessary in most cases. |

Override the cache policy entirely via `cache_policy_id`, `origin_request_policy_id`, and `response_headers_policy_id`.

## Requirements

| Name | Version |
|---|---|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

No external apply-time tools required.

## Inputs

### Required

| Name | Description | Type |
|---|---|---|
| name | Name prefix for all resources; also used as the hosting bucket name (must be globally unique). | `string` |

### General

| Name | Description | Type | Default |
|---|---|---|---|
| routing | URI rewrite style: `spa` or `filesystem`. | `string` | `"spa"` |
| default_version | Fallback version prefix when KVS has neither host nor `active` entries. Also seeds `active` on first apply. | `string` | `"main"` |
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
| additional_origin_headers | Extra custom headers sent to S3. | `list(object({name, value}))` | `[]` |

### Cache Behavior

| Name | Description | Type | Default |
|---|---|---|---|
| cache_policy_id | Default cache policy ID. | `string` | AWS-managed CachingOptimized |
| origin_request_policy_id | Origin request policy ID. | `string` | AWS-managed CORS-S3Origin |
| response_headers_policy_id | Response headers policy ID. | `string` | `null` |
| no_cache_paths | Path patterns served with CachingDisabled. | `list(string)` | `[]` |
| long_cache_paths | Path patterns explicitly served with the default long-cache policy. | `list(string)` | `[]` |
| default_root_object | Object name for `/` requests. | `string` | `"index.html"` |

### KeyValueStore

| Name | Description | Type | Default |
|---|---|---|---|
| kvs_initial_data | Seed entries (`host -> version` or `"active" -> version`). Subsequent edits should happen via the AWS CLI from CI. | `map(string)` | `{}` |

### Logging

| Name | Description | Type | Default |
|---|---|---|---|
| enable_logging | Enable CloudFront access logging. | `bool` | `false` |
| create_logging_bucket | Create a new S3 bucket for logs. | `bool` | `false` |
| logging_bucket_domain_name | Existing logging bucket domain name. | `string` | `null` |
| logging_prefix | Base prefix for log files. | `string` | `""` |
| logging_retention_days | Days to retain logs in the created bucket. | `number` | `90` |

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
| cloudfront_function_arn | ARN of the viewer-request rewriter function. |
| key_value_store_arn | ARN of the KeyValueStore. |
| key_value_store_id | ID of the KeyValueStore. |
| default_version | Apply-time fallback version (also seeded into `active`). |
| deploy_role_arn | ARN of the deploy role (null unless created). |
| deploy_role_name | Name of the deploy role. |
| set_active_version_command | Bash snippet that flips the `active` KVS key to `$VERSION`. |
| invalidation_commands | Map of distribution key -> ready-to-run `aws cloudfront create-invalidation`. Rarely needed. |

## Security Considerations

- Hosting bucket has all four S3 public access block settings enabled by default (inherited from `storage/s3`).
- CloudFront uses OAC, not OAI — supports SSE-KMS and Object Lambda.
- Bucket policy grants `s3:GetObject` only to `cloudfront.amazonaws.com` scoped to the specific distribution ARNs created by this module (defense in depth).
- Optional deploy role uses a fully user-supplied trust policy — no implicit cross-account trust.
- TLS 1.2+ enforced on the viewer side (`minimum_protocol_version` defaults to `TLSv1.2_2021`).
- HTTP -> HTTPS redirect is the default viewer protocol policy.

## Notes

- **Build is your job**: this module does not run a build step. CI produces a `dist/` directory and `aws s3 sync`s it to `s3://<bucket>/<version>/`.
- **First deploy**: with `default_version = "main"`, a fresh apply works as soon as you sync to `s3://<bucket>/main/`. No KVS edit needed for the very first cutover.
- **First request is slow**: CloudFront distributions take 5-15 minutes to deploy globally. `wait_for_deployment = true` (default) blocks `tofu apply` until ready; set to `false` for faster iteration.
- **KVS updates**: only the seed entries are managed via Terraform. Subsequent additions/deletions (preview hosts, `active` flips) belong in CI.
- **Route53 records**: create externally with [`networking/route53`](../../networking/route53) using the `distribution_domain_names` and `distribution_hosted_zone_ids` outputs.
- **ACM certificates**: create externally with [`security/acm_certificate`](../../security/acm_certificate) using a `us_east_1` provider alias.
