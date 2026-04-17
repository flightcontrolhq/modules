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

variable "mode" {
  type        = string
  description = "Hosting mode. 'spa' uses CloudFront error responses to fall back to /index.html with no edge compute. 'filesystem' adds a CloudFront Function for clean URLs and trailing slashes (no Lambda). 'filesystem_previews' adds Lambda@Edge for FC-style deployment-versioned previews and existence-based path resolution (the only mode that creates a Lambda)."
  default     = "spa"

  validation {
    condition     = contains(["spa", "filesystem", "filesystem_previews"], var.mode)
    error_message = "The mode must be one of: 'spa', 'filesystem', 'filesystem_previews'."
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
  description = "Enable versioning on the hosting bucket. Recommended for static sites so you can roll back deployments."
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

variable "origin_path" {
  type        = string
  description = "Optional path prepended to all origin requests (e.g. '/build')."
  default     = null
}

variable "additional_origin_headers" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Extra custom headers to send to the S3 origin (in addition to the mode-driven defaults)."
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
  description = "Optional CloudFront response headers policy ID (e.g. for HSTS, security headers, CORS)."
  default     = null
}

variable "no_cache_paths" {
  type        = list(string)
  description = "Path patterns that should bypass CloudFront caching. Defaults to the root index document so deploys are visible immediately while hashed assets remain long-cached."
  default     = ["/index.html"]
}

variable "long_cache_paths" {
  type        = list(string)
  description = "Path patterns that should use the default long-cache policy explicitly (useful for documentation/clarity in the distribution config). These are typically immutable, hash-named asset directories."
  default     = []
}

variable "default_root_object" {
  type        = string
  description = "Object returned for root URL requests. Defaults to 'index.html'."
  default     = "index.html"
}

variable "spa_error_caching_min_ttl" {
  type        = number
  description = "Minimum TTL (seconds) CloudFront caches the SPA fallback response for. Only applies when mode = 'spa'."
  default     = 10

  validation {
    condition     = var.spa_error_caching_min_ttl >= 0
    error_message = "The spa_error_caching_min_ttl must be >= 0."
  }
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
# Lambda@Edge (filesystem_previews mode only)
################################################################################

variable "lambda_source_dir" {
  type        = string
  description = "Optional override for the Lambda@Edge source directory. Defaults to the bundled handler under '<module>/edge/handler'. Only used when mode = 'filesystem_previews'."
  default     = null
}

variable "lambda_memory_size" {
  type        = number
  description = "Memory size (MB) for the Lambda@Edge function. Capped at 3008 MB by CloudFront."
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda@Edge memory_size must be between 128 and 3008 MB."
  }
}

variable "lambda_timeout" {
  type        = number
  description = "Timeout (seconds) for the Lambda@Edge function. Capped at 30 seconds by CloudFront for origin-request triggers."
  default     = 5

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 30
    error_message = "Lambda@Edge timeout must be between 1 and 30 seconds."
  }
}

variable "lambda_runtime" {
  type        = string
  description = "Lambda@Edge Node.js runtime."
  default     = "nodejs20.x"

  validation {
    condition     = contains(["nodejs18.x", "nodejs20.x", "nodejs22.x"], var.lambda_runtime)
    error_message = "Only Node.js 18/20/22 runtimes are supported for Lambda@Edge."
  }
}

variable "lambda_log_retention_days" {
  type        = number
  description = "CloudWatch log retention for the Lambda@Edge function logs."
  default     = 30
}

variable "static_mode_header_value" {
  type        = string
  description = "Value of the STATIC_MODE custom origin header read by the Lambda@Edge handler. 'spa' falls back to /index.html on missing files; 'filesystem' returns a 404."
  default     = "spa"

  validation {
    condition     = contains(["spa", "filesystem"], var.static_mode_header_value)
    error_message = "The static_mode_header_value must be 'spa' or 'filesystem'."
  }
}

variable "deployment_id_header_value" {
  type        = string
  description = "Value of the X-FC-DEPLOYMENT-ID origin header used to select the active S3 deployment prefix when the CloudFront Function/KVS does not override it."
  default     = "main"
}

variable "preview_url_header_value" {
  type        = string
  description = "Optional value of the X-FC-PREVIEW-URL origin header. When set, the handler resolves preview prefixes from the request's Referer/host."
  default     = ""
}

variable "trailing_slash_enabled" {
  type        = bool
  description = "When true, the Lambda@Edge handler issues a 302 redirect to add trailing slashes on extension-less paths."
  default     = false
}

################################################################################
# CloudFront KeyValueStore (filesystem_previews mode only)
################################################################################

variable "create_key_value_store" {
  type        = bool
  description = "Whether to create a CloudFront KeyValueStore for the filesystem_previews CloudFront Function (host -> deployment prefix lookups). Ignored unless mode = 'filesystem_previews'."
  default     = false
}

variable "kvs_initial_data" {
  type        = map(string)
  description = "Optional seed data for the KeyValueStore as a host -> deployment-prefix map. Written via the KVS import_source."
  default     = {}
}

################################################################################
# Deploy Role (optional)
################################################################################

variable "create_deploy_role" {
  type        = bool
  description = "Whether to create an IAM role that CI can assume to upload to the hosting bucket and create CloudFront invalidations."
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
