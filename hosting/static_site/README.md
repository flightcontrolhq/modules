# Static Site Hosting

End-to-end composite module for hosting static sites on AWS using S3 + CloudFront. Composes [`storage/s3`](../../storage/s3) and [`cdn/cloudfront`](../../cdn/cloudfront).

Every deployment is stored in a versioned S3 directory. A CloudFront KeyValueStore holds a `host -> version` map, and `deployment_cache_mode` chooses whether the active version is resolved before or after CloudFront cache lookup. Promoting or rolling back a build is one `put-key` call against the KVS.

## Features

- **Versioned-by-default**: every deploy lands at `s3://<bucket>/<version>/`, the KVS `active` key points at the live one.
- **Instant rollback**: flip `active` (or any per-host KVS entry) — KVS reads at the edge propagate within seconds.
- **No default CloudFront invalidation**: versioned mode changes the cache key on promotion; stale-while-revalidate mode converges through bounded CDN revalidation.
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
         | rewriter (CFF)         |<------>| KVS |
         |   1. host -> version   |        +-----+
         |   2. rewrite URI:      |
         |      /foo -> /<v>/...  |
         +-----------+------------+
                     | (rewritten URI = cache key)
                     v
         +-----------+------------+
         | S3 Hosting Bucket      |
         | (private, OAC SigV4)   |
         +-----------+------------+
                     | response
                     v
         +-----------+------------+
         | cache-control (CFF)    |
         |   viewer-response      |
         |   sets Cache-Control   |
         |   from rewritten URI   |
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
}
```

The viewer-response function automatically classifies every response as HTML or asset. Hashed assets get `public, max-age=31536000, immutable`. HTML defaults to `no-cache` in versioned mode and `max-age=0, stale-while-revalidate=300` in stale-while-revalidate mode.

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

  deploy_role_creation_enabled = true
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
KVS_ARN=$(tofu output -raw cloudfront_keyvaluestore_arn)
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

The deploy role created when `deploy_role_creation_enabled = true` has exactly the S3 + KVS permissions to do all of this.

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

`deployment_cache_mode` is independent of `routing`:

| Setting | `versioned` | `stale_while_revalidate` |
|---|---|---|
| HTML cache key | Version-specific | Stable and partitioned by viewer `Host` |
| Promotion | KVS pointer flip creates a new cache identity | KVS pointer is resolved on origin request |
| HTML browser default | `no-cache` | `max-age=0, stale-while-revalidate=300` |
| HTML CDN policy | AWS-managed CachingOptimized by default; does not bridge deployments | `public, s-maxage=5, stale-while-revalidate=300, stale-if-error=300` injected on origin response |
| Asset browser policy | `public, max-age=31536000, immutable` | `public, max-age=31536000, immutable` |
| Cutover | Version-specific after an edge observes KVS promotion | Per-page convergence; bounded stale content is allowed |
| Lambda@Edge | No | One function associated with origin request and origin response |

In `versioned` mode, the viewer-request function prepends the active version before cache lookup. Browser HTML validates before reuse, while immutable public asset URLs remain warm in browsers. `cache_policy_id` and `origin_request_policy_id` may be overridden only in this mode. Versioned mode has no origin-response processing: externally uploaded objects with missing or incorrect `Content-Type` are not repaired at cache fill and CloudFront may skip compression.

In `stale_while_revalidate` mode, the viewer URI stays stable. The viewer-request function passes the active version in `X-Ravion-Version`; a Lambda@Edge origin-request trigger resolves the versioned S3 URI, and the same function's origin-response trigger injects CDN cache-fill headers and repairs `Content-Type` on both `200` and `304` responses. The internal version header is forwarded but excluded from the cache key. Module-managed cache and origin request policies are mandatory, so caller values for `cache_policy_id` and `origin_request_policy_id` are rejected.

SWR is appropriate only when bounded stale public content is acceptable. Stale HTML may reference an old hashed asset that is no longer present in the active version on an edge miss. Keep old deployment directories through the stale window and configure correctness-critical routes such as checkout, account, pricing, and inventory in `no_cache_paths`.

The viewer-response function always controls browser-facing headers when `cache_control_enabled = true`; SWR's origin-response headers separately control what CloudFront caches. Tune browser headers with `html_cache_control` and `assets_cache_control`, and use `html_path_overrides` for stable root files.

## Custom response headers (security, CORS, etc.)

For everything *other than* `Cache-Control` — HSTS, CSP, X-Frame-Options, Referrer-Policy, X-Content-Type-Options, CORS, custom headers, header stripping — there are two paths, choose whichever fits your operating model.

### Module-managed (declarative): `response_headers_policy`

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

  response_headers_policy = {
    security_headers_config = {
      strict_transport_security = {
        access_control_max_age_sec = 63072000 # 2 years
        include_subdomains         = true
        preload                    = true
      }
      content_security_policy = {
        content_security_policy = "default-src 'self'; script-src 'self' https://plausible.io; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://plausible.io"
      }
      content_type_options = {}
      frame_options = {
        frame_option = "DENY"
      }
      referrer_policy = {
        referrer_policy = "strict-origin-when-cross-origin"
      }
    }

    custom_headers = [
      {
        header = "Permissions-Policy"
        value  = "camera=(), microphone=(), geolocation=()"
      },
      {
        header = "Cross-Origin-Opener-Policy"
        value  = "same-origin"
      },
    ]

    remove_headers = ["Server", "X-Powered-By"]
  }
}
```

The module creates an `aws_cloudfront_response_headers_policy` from this configuration and attaches it to the default cache behavior alongside the cache-control function.

### Caller-supplied: `response_headers_policy_id`

For org-wide CSP/security baselines managed centrally, pass the existing policy id directly:

```hcl
module "site" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = { main = { ... } }

  response_headers_policy_id = data.aws_cloudfront_response_headers_policy.org_security.id
}
```

`response_headers_policy_id` and `response_headers_policy` can both be set — the caller-supplied id wins on the default behavior, but the module-managed policy is still created and exposed via `module_response_headers_policy_id` so you can attach it elsewhere.

> **Don't put `Cache-Control` in `custom_headers` with `override = true`** unless you intentionally want to overwrite what the cache-control function set. Response-headers policies apply *after* CloudFront Functions, so a policy-set value with override beats the function. The whole point of the function is to discriminate HTML from assets at the URI level, which a static policy can't do.

## Requirements

| Name | Version |
|---|---|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

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
| deployment_cache_mode | Cache consistency model: `versioned` or `stale_while_revalidate`. | `string` | `"versioned"` |
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
| deployment_wait_enabled | Wait for distributions to deploy on apply. | `bool` | `true` |

### Hosting Bucket

| Name | Description | Type | Default |
|---|---|---|---|
| bucket_versioning_enabled | Enable S3 versioning on the hosting bucket. | `bool` | `true` |
| bucket_force_destroy_enabled | Allow destroy of a non-empty bucket. | `bool` | `false` |
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
| cache_policy_id | Optional versioned-mode cache policy ID. Rejected in SWR mode. | `string` | `null` (AWS-managed CachingOptimized effectively) |
| origin_request_policy_id | Optional versioned-mode origin request policy ID. Rejected in SWR mode. | `string` | `null` (AWS-managed CORS-S3Origin effectively) |
| response_headers_policy_id | Externally-managed response-headers policy ID (e.g. an org-wide CSP). Wins over `response_headers_policy` when both are set. | `string` | `null` |
| response_headers_policy | Declarative module-managed response-headers policy: HSTS, CSP, X-Frame-Options, Referrer-Policy, CORS, custom headers, removed headers. See README for the full shape and an example. | `object(...)` | `null` |
| no_cache_paths | Path patterns served with CachingDisabled. | `list(string)` | `[]` |
| default_root_object | Object name for `/` requests. | `string` | `"index.html"` |
| cache_control_enabled | Attach the viewer-response Cache-Control function. | `bool` | `true` |
| html_cache_control | Optional browser Cache-Control value for HTML responses. | `string` | `null` (`no-cache` versioned; bounded SWR in SWR mode) |
| assets_cache_control | Cache-Control value for hashed asset responses (any non-html file extension not in `html_path_overrides`). | `string` | `"public, max-age=31536000, immutable"` |
| html_path_overrides | Exact-match viewer URIs that always get `html_cache_control` regardless of extension. Defaults cover service-worker/PWA/SEO files. | `list(string)` | `["/service-worker.js", "/sw.js", "/manifest.json", "/manifest.webmanifest", "/favicon.ico", "/robots.txt", "/sitemap.xml"]` |

### KeyValueStore

| Name | Description | Type | Default |
|---|---|---|---|
| kvs_initial_data | Seed entries (`host -> version` or `"active" -> version`). Subsequent edits should happen via the AWS CLI from CI. | `map(string)` | `{}` |

### Logging

| Name | Description | Type | Default |
|---|---|---|---|
| logging_enabled | Enable CloudFront access logging. | `bool` | `false` |
| logging_bucket_creation_enabled | Create a new S3 bucket for logs. | `bool` | `false` |
| logging_bucket_domain_name | Existing logging bucket domain name. | `string` | `null` |
| logging_prefix | Base prefix for log files. | `string` | `""` |
| logging_retention_days | Days to retain logs in the created bucket. | `number` | `90` |

### Deploy Role

| Name | Description | Type | Default |
|---|---|---|---|
| deploy_role_creation_enabled | Create an IAM role for CI to assume. | `bool` | `false` |
| deploy_role_trust_policy | Trust policy JSON. Required when `deploy_role_creation_enabled = true`. | `string` | `null` |
| deploy_role_name | Override role name. | `string` | `"<name>-deploy"` |

## Outputs

| Name | Description |
|---|---|
| hosting_bucket_id | Name of the S3 hosting bucket. |
| hosting_bucket_arn | ARN of the S3 hosting bucket. |
| hosting_bucket_regional_domain_name | Regional domain name of the hosting bucket. |
| hosting_bucket_region | AWS region of the hosting bucket. |
| distribution_ids | Map of distribution key -> CloudFront distribution ID. |
| cloudfront_distribution_arns_map | Map of distribution key -> distribution ARN. |
| cloudfront_distribution_arns | List of all CloudFront distribution ARNs. |
| distribution_domain_names | Map of distribution key -> CloudFront domain name. |
| distribution_hosted_zone_ids | Map of distribution key -> Route53 zone ID for alias records. |
| cloudfront_function_arn | ARN of the viewer-request rewriter function. |
| cache_control_function_arn | ARN of the viewer-response Cache-Control writer function. Null when `cache_control_enabled = false`. |
| response_headers_policy_id | ID of the response-headers policy attached to the default behavior (caller-supplied id when set, otherwise the module-managed one, otherwise null). |
| module_response_headers_policy_id | ID of the module-managed response-headers policy. Null when `var.response_headers_policy` is null. |
| cloudfront_keyvaluestore_arn | ARN of the KeyValueStore. |
| key_value_store_id | ID of the KeyValueStore. |
| default_version | Apply-time fallback version (also seeded into `active`). |
| deploy_role_arn | ARN of the deploy role (null unless created). |
| deploy_role_name | Name of the deploy role. |
| set_active_version_command | Bash snippet that flips the `active` KVS key to `$VERSION`. |
| invalidation_commands | Map of distribution key -> ready-to-run `aws cloudfront create-invalidation`. Rarely needed. |

## Security Considerations

- Hosting bucket has all four S3 public access block settings enabled by default (inherited from `storage/s3`).
- CloudFront uses OAC, not OAI — supports SSE-KMS and Object Lambda.
- Bucket policy grants scoped `s3:GetObject` and `s3:ListBucket` to `cloudfront.amazonaws.com`, allowing missing objects to remain `404` while genuine authorization failures remain `403`.
- Optional deploy role uses a fully user-supplied trust policy — no implicit cross-account trust.
- TLS 1.2+ enforced on the viewer side (`minimum_protocol_version` defaults to `TLSv1.2_2021`).
- HTTP -> HTTPS redirect is the default viewer protocol policy.

## Notes

- **Build is your job**: this module does not run a build step. CI produces a `dist/` directory and `aws s3 sync`s it to `s3://<bucket>/<version>/`.
- **First deploy**: with `default_version = "main"`, a fresh apply works as soon as you sync to `s3://<bucket>/main/`. No KVS edit needed for the very first cutover.
- **First request is slow**: CloudFront distributions take 5-15 minutes to deploy globally. `deployment_wait_enabled = true` (default) blocks `tofu apply` until ready; set to `false` for faster iteration.
- **KVS updates**: only the seed entries are managed via Terraform. Subsequent additions/deletions (preview hosts, `active` flips) belong in CI.
- **Route53 records**: create externally with [`networking/route53`](../../networking/route53) using the `distribution_domain_names` and `distribution_hosted_zone_ids` outputs.
- **ACM certificates**: create externally with [`security/acm_certificate`](../../security/acm_certificate) using a `us_east_1` provider alias.
