################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module. Also used as the hosting bucket name (must be globally unique and a valid S3 bucket name)."

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 63
    error_message = "The name must be between 3 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.name))
    error_message = "The name must be a valid S3 bucket name: lowercase letters, numbers, hyphens, periods; must start and end with a letter or number."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "routing" {
  type        = string
  description = "URI rewriting style applied at the edge before the version prefix is added. 'spa' rewrites every non-asset path to /<version>/index.html so a client-side router takes over. 'filesystem' rewrites /foo and /foo/ to /<version>/foo/index.html and serves /foo.js etc. as-is. Both styles are versioned identically."
  default     = "spa"

  validation {
    condition     = contains(["spa", "filesystem"], var.routing)
    error_message = "The routing must be 'spa' or 'filesystem'."
  }
}

variable "default_version" {
  type        = string
  description = "Version prefix used when KVS has neither a host-specific entry nor an 'active' key. Also used as the seed value for the 'active' KVS key on first apply. Pick a stable name like 'main' so the first deploy can sync to s3://<bucket>/<default_version>/ without further setup."
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.default_version))
    error_message = "The default_version must contain only letters, numbers, '.', '_', '-', '/'."
  }
}

################################################################################
# Distributions
################################################################################

variable "distributions" {
  type = map(object({
    aliases             = optional(list(string), [])
    acm_certificate_arn = optional(string)
    comment             = optional(string)
    enabled             = optional(bool, true)
  }))
  description = "A map of CloudFront distributions to create. Each entry shares the same S3 origin and cache behaviors but has its own aliases and ACM certificate. Defaults to a single 'main' distribution with no aliases (CloudFront default certificate)."
  default = {
    main = {}
  }

  validation {
    condition     = length(var.distributions) > 0
    error_message = "At least one distribution must be specified."
  }
}

variable "price_class" {
  type        = string
  description = "CloudFront price class. 'PriceClass_100' (US/Canada/Europe) is the cheapest; 'PriceClass_All' covers every edge location."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "The price_class must be 'PriceClass_100', 'PriceClass_200', or 'PriceClass_All'."
  }
}

variable "minimum_protocol_version" {
  type        = string
  description = "Minimum TLS version for viewer connections (only applies when an ACM certificate is set on the distribution)."
  default     = "TLSv1.2_2021"
}

variable "geo_restriction_type" {
  type        = string
  description = "Geo restriction type: 'none', 'whitelist', or 'blacklist'."
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "The geo_restriction_type must be 'none', 'whitelist', or 'blacklist'."
  }
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "ISO 3166-1-alpha-2 country codes for geo restriction."
  default     = []
}

variable "web_acl_id" {
  type        = string
  description = "ARN of a global-scope WAFv2 Web ACL to associate with all distributions."
  default     = null

  validation {
    condition     = var.web_acl_id == null || can(regex("^arn:aws:wafv2:", var.web_acl_id))
    error_message = "The web_acl_id must be a valid WAFv2 Web ACL ARN."
  }
}

variable "wait_for_deployment" {
  type        = bool
  description = "Whether to wait for each distribution to be deployed before completing apply."
  default     = true
}

################################################################################
# Hosting Bucket
################################################################################

variable "bucket_versioning" {
  type        = bool
  description = "Enable versioning on the hosting bucket. Disable only if you know what you're doing — this is independent of the per-deploy version prefix and protects against accidental overwrites."
  default     = true
}

variable "bucket_force_destroy" {
  type        = bool
  description = "Allow `tofu destroy` to delete the hosting bucket even if it is not empty. Useful for ephemeral environments; dangerous in production."
  default     = false
}

variable "bucket_lifecycle_rules" {
  type = list(object({
    id      = string
    enabled = optional(bool, true)
    prefix  = optional(string)
    tags    = optional(map(string))
    expiration = optional(object({
      days                         = optional(number)
      date                         = optional(string)
      expired_object_delete_marker = optional(bool)
    }))
    noncurrent_version_expiration = optional(object({
      noncurrent_days           = optional(number)
      newer_noncurrent_versions = optional(number)
    }))
    transitions = optional(list(object({
      days          = optional(number)
      date          = optional(string)
      storage_class = string
    })), [])
    noncurrent_version_transitions = optional(list(object({
      noncurrent_days           = optional(number)
      newer_noncurrent_versions = optional(number)
      storage_class             = string
    })), [])
    abort_incomplete_multipart_upload_days = optional(number)
  }))
  description = "Lifecycle rules for the hosting bucket. Defaults to expiring noncurrent versions after 30 days and aborting incomplete multipart uploads after 7 days; pass an empty list to disable defaults."
  default = [
    {
      id = "expire-noncurrent-versions"
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}

variable "kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for SSE-KMS encryption of the hosting bucket. If null, SSE-S3 (AES256) is used."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be null or a valid KMS key ARN."
  }
}

################################################################################
# Origin
################################################################################

variable "origin_shield_region" {
  type        = string
  description = "Optional AWS region to enable CloudFront Origin Shield in. Reduces origin load and improves cache hit ratio for global distributions."
  default     = null
}

variable "additional_origin_headers" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Extra custom headers to send to the S3 origin."
  default     = []
}

################################################################################
# Cache Behavior
################################################################################

variable "cache_policy_id" {
  type        = string
  description = "CloudFront cache policy ID for the default behavior. Defaults to AWS-managed CachingOptimized (long-cache, suitable for hashed assets)."
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

variable "origin_request_policy_id" {
  type        = string
  description = "CloudFront origin request policy ID. Defaults to AWS-managed CORS-S3Origin (forwards Origin/Access-Control-* headers, no cookies/query strings)."
  default     = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
}

variable "response_headers_policy_id" {
  type        = string
  description = "ID of an externally-managed CloudFront response-headers policy to attach to the default behavior. Use when you have a centrally-managed policy (e.g. an org-wide CSP) you want to share across distributions. Mutually exclusive with `response_headers_policy` — when both are set, this caller-supplied id wins. Note: do NOT put `Cache-Control` in this policy with override=true; it will fight the cache-control function."
  default     = null
}

variable "response_headers_policy" {
  type = object({
    security_headers_config = optional(object({
      strict_transport_security = optional(object({
        access_control_max_age_sec = number
        include_subdomains         = optional(bool, true)
        preload                    = optional(bool, false)
        override                   = optional(bool, true)
      }))
      content_security_policy = optional(object({
        content_security_policy = string
        override                = optional(bool, true)
      }))
      content_type_options = optional(object({
        override = optional(bool, true)
      }))
      frame_options = optional(object({
        frame_option = string
        override     = optional(bool, true)
      }))
      referrer_policy = optional(object({
        referrer_policy = string
        override        = optional(bool, true)
      }))
      xss_protection = optional(object({
        protection = bool
        mode_block = optional(bool, true)
        report_uri = optional(string)
        override   = optional(bool, true)
      }))
    }))

    cors_config = optional(object({
      access_control_allow_credentials = bool
      access_control_allow_headers     = list(string)
      access_control_allow_methods     = list(string)
      access_control_allow_origins     = list(string)
      access_control_expose_headers    = optional(list(string), [])
      access_control_max_age_sec       = optional(number, 600)
      origin_override                  = optional(bool, false)
    }))

    custom_headers = optional(list(object({
      header   = string
      value    = string
      override = optional(bool, true)
    })), [])

    remove_headers = optional(list(string), [])
  })
  description = <<-EOT
    Declarative configuration for a module-managed CloudFront response-headers policy. Use this for security headers (HSTS, CSP, X-Frame-Options, Referrer-Policy, X-Content-Type-Options nosniff), CORS, arbitrary custom response headers, and stripped headers. Mirrors the AWS `aws_cloudfront_response_headers_policy` resource shape — see the module README for examples.

    Coexists with the cache-control function: the function writes Cache-Control on every response in viewer-response, then the response-headers policy applies. Don't put Cache-Control in `custom_headers` with override=true unless you intentionally want to overwrite what the function set.

    Mutually exclusive with `response_headers_policy_id` — when both are set, the caller-supplied id wins on the default behavior. Set to null (default) to skip creating any module-managed policy.
  EOT
  default     = null

  validation {
    condition = var.response_headers_policy == null ? true : (
      try(var.response_headers_policy.security_headers_config.frame_options, null) == null ||
      contains(["DENY", "SAMEORIGIN"], try(var.response_headers_policy.security_headers_config.frame_options.frame_option, ""))
    )
    error_message = "frame_options.frame_option must be either 'DENY' or 'SAMEORIGIN'."
  }
}

variable "no_cache_paths" {
  type        = list(string)
  description = "Path patterns that should bypass CloudFront caching. Empty by default — versioned deploys make every promotion a fresh cache key, so per-path cache busting is rarely needed."
  default     = []
}

variable "default_root_object" {
  type        = string
  description = "Object name resolved when a viewer requests '/'. Defaults to 'index.html'."
  default     = "index.html"
}

################################################################################
# Cache-Control (viewer-response CloudFront Function)
#
# A viewer-response function classifies every response by the rewritten URI
# shape and writes Cache-Control accordingly:
#
#   - URI in html_path_overrides (service workers, PWA manifests, SEO files),
#     or contains a dotted segment, or has no extension, or ends in
#     .html / .htm  ->  html_cache_control
#   - any other extension                                  ->  assets_cache_control
#
# This sidesteps the cache-behavior matching pitfall that bit ENG-4785: the
# behavior-level response_headers_policy_id can only see the original viewer
# URI (pre-rewrite), but a viewer-response function sees the rewritten URI
# where HTML vs asset is unambiguous from the file extension.
################################################################################

variable "manage_cache_control" {
  type        = bool
  description = "Whether the module attaches a viewer-response CloudFront Function that writes Cache-Control on every response. Disable to delegate Cache-Control to S3 object metadata or to a caller-supplied response_headers_policy_id."
  default     = true
}

variable "html_cache_control" {
  type        = string
  description = "Cache-Control header value emitted by the cache-control function for HTML responses (URI has no extension, ends in .html/.htm, contains a dotted segment, or matches html_path_overrides). Defaults to a short CDN s-maxage with a long stale-while-revalidate window so version flips propagate within seconds without blocking on a cache miss, and so browsers never store HTML as immutable."
  default     = "s-maxage=5, stale-while-revalidate=31536000"
}

variable "assets_cache_control" {
  type        = string
  description = "Cache-Control header value emitted by the cache-control function for asset responses (URI has any non-html file extension and is not in html_path_overrides). Defaults to a one-year immutable browser cache, which is safe because every asset URL is pinned to /<version>/... by the rewriter so bytes never collide between deploys."
  default     = "public, max-age=31536000, immutable"
}

variable "html_path_overrides" {
  type        = list(string)
  description = "Exact-match viewer URIs that always receive html_cache_control regardless of file extension. Defaults cover the common service-worker, PWA, and SEO files where stable, non-hashed URLs MUST NOT be cached as immutable — a wedged service worker can brick a site until the user clears site data. Pass an empty list to opt out of the defaults; extend it for project-specific files."
  default = [
    "/service-worker.js",
    "/sw.js",
    "/manifest.json",
    "/manifest.webmanifest",
    "/favicon.ico",
    "/robots.txt",
    "/sitemap.xml",
  ]
}

################################################################################
# CloudFront KeyValueStore (always created)
################################################################################

variable "kvs_initial_data" {
  type        = map(string)
  description = "Optional seed entries for the KeyValueStore. Use `host -> version` to pin specific aliases (e.g. {\"staging.example.com\" = \"v_staging\"}) or `\"active\" -> version` to override the default_version seed. Subsequent edits should happen via `aws cloudfront-keyvaluestore put-key` from CI to avoid Terraform churn for ephemeral previews."
  default     = {}
}

################################################################################
# Logging
################################################################################

variable "enable_logging" {
  type        = bool
  description = "Enable CloudFront access logging."
  default     = false
}

variable "create_logging_bucket" {
  type        = bool
  description = "Whether to create a new S3 bucket for CloudFront access logs. Ignored if enable_logging is false."
  default     = false
}

variable "logging_bucket_domain_name" {
  type        = string
  description = "Domain name of an existing S3 bucket for access logs (e.g. 'mybucket.s3.amazonaws.com'). Used when enable_logging is true and create_logging_bucket is false."
  default     = null
}

variable "logging_prefix" {
  type        = string
  description = "Base S3 key prefix for access logs. Each distribution logs under '<logging_prefix><distribution_key>/'."
  default     = ""
}

variable "logging_retention_days" {
  type        = number
  description = "Days to retain CloudFront access logs (only applies to the bucket created when create_logging_bucket = true)."
  default     = 90
}

################################################################################
# Deploy Role (optional)
################################################################################

variable "create_deploy_role" {
  type        = bool
  description = "Whether to create an IAM role that CI can assume to upload to the hosting bucket and flip the active version in KVS."
  default     = false
}

variable "deploy_role_trust_policy" {
  type        = string
  description = "Trust policy JSON for the deploy role. Required when create_deploy_role = true. Typically grants sts:AssumeRoleWithWebIdentity to a GitHub OIDC provider or sts:AssumeRole to a CI account."
  default     = null

  validation {
    condition     = var.deploy_role_trust_policy == null || can(jsondecode(var.deploy_role_trust_policy))
    error_message = "The deploy_role_trust_policy must be valid JSON."
  }
}

variable "deploy_role_name" {
  type        = string
  description = "Override name for the deploy role. Defaults to '<name>-deploy'."
  default     = null
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
