# AWS CloudFront

Creates and manages AWS CloudFront distributions with support for multiple distributions (domain groups), multiple origin types, modern cache policies, Origin Access Control (OAC) for S3, WAF integration, and optional access logging.

## Features

- **Multiple Distributions**: Create multiple CloudFront distributions sharing the same origins and cache behaviors, each with its own custom domains and SSL certificate
- **Multiple Origins**: Support for S3 and custom (ALB, API Gateway, HTTP) origins with per-origin configuration
- **Modern Cache Policies**: Uses cache policies and origin request policies (no legacy `forwarded_values`)
- **Origin Access Control**: Automatic OAC creation for S3 origins (recommended over legacy OAI)
- **SSL/TLS**: Custom ACM certificates with configurable minimum TLS version, SNI support
- **WAF Integration**: Associate a WAFv2 Web ACL (global scope) for edge protection
- **Access Logging**: Optional S3 logging bucket with lifecycle management, per-distribution log prefixes
- **Edge Functions**: Support for CloudFront Functions and Lambda@Edge associations
- **Custom Error Pages**: Configurable error response handling with custom pages
- **Geo Restrictions**: Whitelist or blacklist countries using ISO 3166-1-alpha-2 codes
- **HTTP/3 Support**: HTTP/2 and HTTP/3 enabled by default
- **Origin Shield**: Optional regional caching layer to reduce origin load

## Usage

### Basic S3 Static Website

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-website"

  distributions = {
    main = {}
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  default_root_object = "index.html"
}
```

### ALB Origin with HTTPS

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-api"

  distributions = {
    main = {
      aliases             = ["api.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id              = "alb"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  }
}
```

### Multi-Origin (S3 + ALB) with Ordered Cache Behaviors

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-assets.s3.us-east-1.amazonaws.com"
      s3_origin   = true
    },
    {
      origin_id              = "alb-api"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  ordered_cache_behaviors = [
    {
      path_pattern           = "/api/*"
      target_origin_id       = "alb-api"
      viewer_protocol_policy = "https-only"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
    }
  ]

  default_root_object = "index.html"
}
```

### Multiple Distributions with Different Domain Groups

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    production = {
      aliases             = ["app.example.com", "www.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/prod-cert"
    }
    staging = {
      aliases             = ["staging.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/staging-cert"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-assets.s3.us-east-1.amazonaws.com"
      s3_origin   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }
}
```

### Production with WAF and Logging

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id              = "alb"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  }

  # WAF
  web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc-123"

  # Logging
  enable_logging        = true
  create_logging_bucket = true
  logging_prefix        = "cloudfront/"

  tags = {
    Environment = "production"
  }
}
```

### With Custom Error Responses

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-spa"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  custom_error_responses = [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  ]

  default_root_object = "index.html"
}
```

### With Geo Restrictions

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  # Only allow US and Canada
  geo_restriction_type      = "whitelist"
  geo_restriction_locations = ["US", "CA"]
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources created by this module. | `string` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |

### Distributions

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| distributions | A map of CloudFront distributions to create. Each key is a distribution identifier. | `map(object({...}))` | n/a | yes |
| distributions[].aliases | CNAMEs for this distribution. | `list(string)` | `[]` | no |
| distributions[].acm_certificate_arn | ACM certificate ARN for this distribution's domains. | `string` | `null` | no |
| distributions[].comment | Distribution-specific comment. | `string` | `"${name}-${key}"` | no |
| distributions[].enabled | Whether this distribution accepts requests. | `bool` | `true` | no |

### Origins

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| origins | A list of origin configurations for the CloudFront distribution. | `list(object({...}))` | n/a | yes |
| origins[].origin_id | Unique identifier for the origin. | `string` | n/a | yes |
| origins[].domain_name | Origin domain name. | `string` | n/a | yes |
| origins[].origin_path | Path prefix appended to the origin domain name. | `string` | `null` | no |
| origins[].origin_protocol_policy | Protocol policy for custom origins: `http-only`, `https-only`, `match-viewer`. | `string` | `"https-only"` | no |
| origins[].http_port | HTTP port for the origin. | `number` | `80` | no |
| origins[].https_port | HTTPS port for the origin. | `number` | `443` | no |
| origins[].origin_ssl_protocols | SSL/TLS protocols for the origin. | `list(string)` | `["TLSv1.2"]` | no |
| origins[].origin_keepalive_timeout | Keep-alive timeout in seconds. | `number` | `null` | no |
| origins[].origin_read_timeout | Read timeout in seconds. | `number` | `null` | no |
| origins[].origin_access_control_id | Override to use an externally-managed OAC. | `string` | `null` | no |
| origins[].connection_attempts | Number of connection attempts (1-3). | `number` | `null` | no |
| origins[].connection_timeout | Connection timeout in seconds (1-10). | `number` | `null` | no |
| origins[].custom_headers | List of custom headers to send to the origin. | `list(object({name, value}))` | `[]` | no |
| origins[].origin_shield | Origin Shield configuration. | `object({enabled, origin_shield_region})` | `null` | no |
| origins[].s3_origin | Whether this is an S3 origin (creates OAC). | `bool` | `false` | no |

### Default Cache Behavior

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| default_cache_behavior | The default cache behavior configuration. | `object({...})` | n/a | yes |
| default_cache_behavior.target_origin_id | Origin ID for the default cache behavior. | `string` | n/a | yes |
| default_cache_behavior.viewer_protocol_policy | Viewer protocol policy: `allow-all`, `https-only`, `redirect-to-https`. | `string` | n/a | yes |
| default_cache_behavior.allowed_methods | HTTP methods to allow. | `list(string)` | `["GET", "HEAD"]` | no |
| default_cache_behavior.cached_methods | HTTP methods to cache. | `list(string)` | `["GET", "HEAD"]` | no |
| default_cache_behavior.compress | Whether to compress content. | `bool` | `true` | no |
| default_cache_behavior.cache_policy_id | Cache policy ID. | `string` | `null` | no |
| default_cache_behavior.origin_request_policy_id | Origin request policy ID. | `string` | `null` | no |
| default_cache_behavior.response_headers_policy_id | Response headers policy ID. | `string` | `null` | no |
| default_cache_behavior.function_associations | CloudFront Function associations. | `list(object({event_type, function_arn}))` | `[]` | no |
| default_cache_behavior.lambda_function_associations | Lambda@Edge associations. | `list(object({event_type, lambda_arn, include_body}))` | `[]` | no |
| default_cache_behavior.realtime_log_config_arn | Real-time log configuration ARN. | `string` | `null` | no |

### Ordered Cache Behaviors

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ordered_cache_behaviors | An ordered list of cache behaviors with path patterns. Same fields as default_cache_behavior plus `path_pattern`. | `list(object({...}))` | `[]` | no |

### Distribution Settings

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| price_class | Price class: `PriceClass_100`, `PriceClass_200`, `PriceClass_All`. | `string` | `"PriceClass_100"` | no |
| http_version | Maximum HTTP version: `http1.1`, `http2`, `http2and3`. | `string` | `"http2and3"` | no |
| is_ipv6_enabled | Whether IPv6 is enabled. | `bool` | `true` | no |
| default_root_object | Object returned for root URL requests (e.g., `index.html`). | `string` | `null` | no |
| retain_on_delete | Retain (disable) the distribution on delete instead of removing it. | `bool` | `false` | no |
| wait_for_deployment | Wait for the distribution to deploy before completing. | `bool` | `true` | no |

### SSL/TLS

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| minimum_protocol_version | Minimum TLS version for viewer connections. | `string` | `"TLSv1.2_2021"` | no |
| ssl_support_method | HTTPS serving method: `sni-only`, `vip`, `static-ip`. | `string` | `"sni-only"` | no |

### Restrictions

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| geo_restriction_type | Geo restriction type: `none`, `whitelist`, `blacklist`. | `string` | `"none"` | no |
| geo_restriction_locations | ISO 3166-1-alpha-2 country codes for geo restriction. | `list(string)` | `[]` | no |

### Custom Error Responses

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| custom_error_responses | Custom error response configurations. | `list(object({...}))` | `[]` | no |
| custom_error_responses[].error_code | HTTP error code (400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504). | `number` | n/a | yes |
| custom_error_responses[].response_code | HTTP response code to return. | `number` | `null` | no |
| custom_error_responses[].response_page_path | Path to the custom error page. | `string` | `null` | no |
| custom_error_responses[].error_caching_min_ttl | Minimum TTL in seconds for caching this error. | `number` | `null` | no |

### WAF

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| web_acl_id | WAFv2 Web ACL ARN (global scope) to associate with the distribution. | `string` | `null` | no |

### Logging

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_logging | Enable access logging. | `bool` | `false` | no |
| logging_bucket_domain_name | Domain name of an existing S3 bucket for logs. | `string` | `null` | no |
| logging_prefix | Base S3 key prefix for log files. Each distribution logs under `<prefix><key>/`. | `string` | `""` | no |
| logging_include_cookies | Include cookies in access logs. | `bool` | `false` | no |
| create_logging_bucket | Create a new S3 bucket for logging. | `bool` | `false` | no |
| logging_bucket_retention_days | Days to retain logs in the created bucket. | `number` | `90` | no |

### Origin Access Control

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| create_origin_access_control | Create OAC resources for S3 origins. | `bool` | `true` | no |
| origin_access_control_origin_type | OAC origin type: `s3`, `mediastore`, `mediapackagev2`, `lambda`. | `string` | `"s3"` | no |
| origin_access_control_signing_behavior | OAC signing behavior: `always`, `never`, `no-override`. | `string` | `"always"` | no |
| origin_access_control_signing_protocol | OAC signing protocol. | `string` | `"sigv4"` | no |

## Outputs

| Name | Description |
|------|-------------|
| distribution_ids | A map of distribution key to CloudFront distribution ID. |
| distribution_arns | A map of distribution key to CloudFront distribution ARN. |
| distribution_domain_names | A map of distribution key to CloudFront distribution domain name. |
| distribution_hosted_zone_ids | A map of distribution key to Route 53 zone ID for alias records. |
| distribution_statuses | A map of distribution key to current distribution status. |
| distribution_etags | A map of distribution key to current distribution ETag. |
| origin_access_control_ids | A map of origin_id to OAC ID for S3 origins. |
| logging_bucket_id | The ID of the logging S3 bucket (null if not created). |
| logging_bucket_arn | The ARN of the logging S3 bucket (null if not created). |
| logging_bucket_domain_name | The domain name of the logging S3 bucket (null if not created). |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          AWS CloudFront Module                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                     CloudFront Distributions                           │  │
│  │  • One per entry in var.distributions (for_each)                      │  │
│  │  • Per-distribution: aliases, ACM cert, comment, enabled              │  │
│  │  • Shared: origins, cache behaviors, settings, WAF, restrictions      │  │
│  │  • HTTP/2 and HTTP/3 by default                                       │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Origins            │  │   Cache Behaviors    │  │   Viewer Cert      │  │
│  │  • S3 (with OAC)     │  │  • Default behavior  │  │  • ACM certificate │  │
│  │  • ALB / Custom HTTP │  │  • Ordered behaviors  │  │  • TLSv1.2_2021   │  │
│  │  • Origin Shield     │  │  • Cache policies     │  │  • SNI-only        │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Origin Access Ctrl │  │   Access Logging     │  │   WAF / Restrict   │  │
│  │  • Per S3 origin     │  │  • Optional S3 bucket│  │  • WAFv2 Web ACL   │  │
│  │  • SigV4 signing     │  │  • Per-dist prefixes │  │  • Geo restrictions│  │
│  │  • Shared across all │  │  • Lifecycle mgmt    │  │  • Error responses │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       CDN/CLOUDFRONT TERRAFORM MODULE                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │       DISTRIBUTIONS             │   │            ORIGINS                      │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • distributions (required)      │   │ • origins (required)                    │  ║
║  │ • tags                      │   │   └─ aliases                    │   │   └─ origin_id, domain_name             │  ║
║  └─────────────────────────────┘   │   └─ acm_certificate_arn        │   │   └─ s3_origin, origin_path             │  ║
║                                    │   └─ comment, enabled           │   │   └─ protocol, ports, timeouts          │  ║
║                                    └─────────────────────────────────┘   │   └─ custom_headers, origin_shield      │  ║
║                                                                          └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │  DEFAULT CACHE BEHAVIOR     │   │  ORDERED CACHE BEHAVIORS        │   │      DISTRIBUTION SETTINGS              │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • target_origin_id          │   │ • path_pattern                  │   │ • price_class                           │  ║
║  │ • viewer_protocol_policy    │   │ • target_origin_id              │   │ • http_version                          │  ║
║  │ • allowed/cached_methods    │   │ • viewer_protocol_policy        │   │ • is_ipv6_enabled                       │  ║
║  │ • cache_policy_id           │   │ • cache_policy_id               │   │ • default_root_object                   │  ║
║  │ • origin_request_policy_id  │   │ • origin_request_policy_id      │   │ • retain_on_delete                      │  ║
║  │ • function_associations     │   │ • function_associations         │   │ • wait_for_deployment                   │  ║
║  │ • lambda_fn_associations    │   │ • lambda_fn_associations        │   └─────────────────────────────────────────┘  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘                                                 ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       SSL/TLS               │   │      RESTRICTIONS               │   │          WAF & ERRORS                   │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • minimum_protocol_version  │   │ • geo_restriction_type          │   │ • web_acl_id                            │  ║
║  │ • ssl_support_method        │   │ • geo_restriction_locations     │   │ • custom_error_responses                │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐                                                 ║
║  │       LOGGING               │   │   ORIGIN ACCESS CONTROL         │                                                 ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤                                                 ║
║  │ • enable_logging            │   │ • create_origin_access_control  │                                                 ║
║  │ • create_logging_bucket     │   │ • oac_origin_type               │                                                 ║
║  │ • logging_bucket_domain_name│   │ • oac_signing_behavior          │                                                 ║
║  │ • logging_prefix            │   │ • oac_signing_protocol          │                                                 ║
║  │ • logging_include_cookies   │   └─────────────────────────────────┘                                                 ║
║  │ • logging_bucket_retention  │                                                                                       ║
║  └─────────────────────────────┘                                                                                       ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                           aws_cloudfront_origin_access_control.this                                          │    ║
║    │  • for_each over S3 origins (where s3_origin = true)                                                        │    ║
║    │  • SigV4 signing, configurable behavior and origin type                                                     │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                              aws_cloudfront_distribution.this                                                 │    ║
║    │                       (for_each = var.distributions — CORE RESOURCE)                                         │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  Per-distribution: enabled, comment, aliases, acm_certificate_arn, logging prefix, tags                     │    ║
║    │  Shared: origins, default_cache_behavior, ordered_cache_behaviors, price_class, http_version, WAF           │    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────────┐  ┌────────────────────────┐  ┌──────────────────────────────────────────────────┐  │    ║
║    │  │ dynamic "origin"    │  │ default_cache_behavior  │  │ dynamic "ordered_cache_behavior"                │  │    ║
║    │  │  • S3 + custom      │  │  • Policies, methods    │  │  • Path-based routing                          │  │    ║
║    │  │  • OAC for S3       │  │  • Edge functions       │  │  • Per-path policies and functions             │  │    ║
║    │  │  • Origin Shield    │  └────────────────────────┘  └──────────────────────────────────────────────────┘  │    ║
║    │  └─────────────────────┘                                                                                    │    ║
║    │  ┌──────────────────────────────┐  ┌──────────────────────────┐  ┌────────────────────────────────────────┐  │    ║
║    │  │ dynamic "custom_error_resp"  │  │   viewer_certificate     │  │ dynamic "logging_config"              │  │    ║
║    │  │  • Custom error pages        │  │  • Default / ACM cert    │  │  • Per-distribution prefix            │  │    ║
║    │  │  • Cache TTL overrides       │  │  • TLS version, SNI      │  │  • Shared or created bucket           │  │    ║
║    │  └──────────────────────────────┘  └──────────────────────────┘  └────────────────────────────────────────┘  │    ║
║    │  ┌──────────────────────────┐                                                                                │    ║
║    │  │   restrictions           │                                                                                │    ║
║    │  │  • Geo whitelist/blacklist│                                                                               │    ║
║    │  └──────────────────────────┘                                                                                │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    Logging S3 Bucket (Optional)                                              │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │  aws_s3_bucket.logging[0]                    (count = create_logging_bucket ? 1 : 0)                        │    ║
║    │  aws_s3_bucket_ownership_controls.logging[0] (BucketOwnerPreferred for CF logging)                          │    ║
║    │  aws_s3_bucket_acl.logging[0]                (log-delivery-write)                                           │    ║
║    │  aws_s3_bucket_lifecycle_configuration[0]    (expiration after N days)                                       │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │     DISTRIBUTIONS (maps by key)         │   │      ORIGIN ACCESS CONTROL              │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • distribution_ids                      │   │ • origin_access_control_ids             │                            ║
║  │ • distribution_arns                     │   └─────────────────────────────────────────┘                            ║
║  │ • distribution_domain_names             │                                                                          ║
║  │ • distribution_hosted_zone_ids          │   ┌─────────────────────────────────────────┐                            ║
║  │ • distribution_statuses                 │   │           LOGGING                       │                            ║
║  │ • distribution_etags                    │   ├─────────────────────────────────────────┤                            ║
║  └─────────────────────────────────────────┘   │ • logging_bucket_id                     │                            ║
║                                                │ • logging_bucket_arn                    │                            ║
║                                                │ • logging_bucket_domain_name            │                            ║
║                                                └─────────────────────────────────────────┘                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_cloudfront_distribution` | 1 per entry in `var.distributions` | CloudFront distribution per domain group |
| `aws_cloudfront_origin_access_control` | 0 to N | OAC per S3 origin (shared across distributions) |
| `aws_s3_bucket` (logging) | 0 or 1 | Access logs bucket (if `create_logging_bucket = true`) |
| `aws_s3_bucket_ownership_controls` | 0 or 1 | Logging bucket ownership (if logging bucket created) |
| `aws_s3_bucket_acl` | 0 or 1 | Logging bucket ACL (if logging bucket created) |
| `aws_s3_bucket_lifecycle_configuration` | 0 or 1 | Log retention (if logging bucket created) |

## Security Considerations

- **TLS 1.2 Minimum**: Default `minimum_protocol_version` is `TLSv1.2_2021`, enforcing modern TLS for all viewer connections.
- **Origin Access Control**: S3 origins use OAC (not legacy OAI) to securely sign requests with SigV4. You must also configure S3 bucket policies to allow the CloudFront distribution principal.
- **HTTPS by Default**: HTTP/2 and HTTP/3 are enabled by default. Use `redirect-to-https` viewer protocol policy to enforce HTTPS.
- **WAF Integration**: Associate a WAFv2 Web ACL (global scope) for DDoS protection, rate limiting, and request filtering at the edge.
- **No Public S3 Access**: When using OAC, S3 buckets should not have public access enabled. CloudFront signs requests on behalf of viewers.
- **Certificate Validation**: ACM certificate ARNs are validated to ensure they are in the correct format. ACM certificates for CloudFront must be in `us-east-1`.

## Notes

- **Modern Cache Policies Only**: This module uses cache policies and origin request policies instead of legacy `forwarded_values`. Reference AWS managed policies by ID or create custom policies outside this module.
- **OAC Only (No OAI)**: Only Origin Access Control is supported. OAI is legacy and does not work with S3 bucket policies using KMS encryption or S3 Object Lambda.
- **Multi-Distribution**: All distributions share the same origins, cache behaviors, and settings. Each distribution gets its own aliases, ACM certificate, and logging prefix. Use this for serving the same content under different domain groups.
- **Logging Prefixes**: When logging is enabled, each distribution logs under `<logging_prefix><distribution_key>/` to keep logs separated.
- **Route53 Records**: Create Route53 alias records externally using the `distribution_domain_names` and `distribution_hosted_zone_ids` outputs.
- **ACM Certificates**: CloudFront requires ACM certificates in `us-east-1` regardless of where other resources are deployed. Provision certificates externally and pass the ARN.
- **Price Classes**: `PriceClass_100` (US, Canada, Europe) is the default. Use `PriceClass_200` to add Asia/Middle East/Africa, or `PriceClass_All` for all edge locations.
- **S3 Bucket Policy**: After creating the distribution, update the S3 bucket policy to allow `s3:GetObject` from the CloudFront distribution. Use the `distribution_arns` output to construct the policy.
