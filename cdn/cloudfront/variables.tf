################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 63
    error_message = "The name must be between 1 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name))
    error_message = "The name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "distributions" {
  type = map(object({
    aliases             = optional(list(string), [])
    acm_certificate_arn = optional(string)
    comment             = optional(string)
    enabled             = optional(bool, true)
  }))
  description = "A map of CloudFront distributions to create. Each key is a distribution identifier. All distributions share origins, cache behaviors, and other settings."

  validation {
    condition     = length(var.distributions) > 0
    error_message = "At least one distribution must be specified."
  }

  validation {
    condition     = alltrue([for k, v in var.distributions : length(v.aliases) == 0 || v.acm_certificate_arn != null])
    error_message = "An acm_certificate_arn is required when aliases are specified."
  }

  validation {
    condition     = alltrue([for k, v in var.distributions : v.acm_certificate_arn == null || can(regex("^arn:aws:acm:", v.acm_certificate_arn))])
    error_message = "The acm_certificate_arn must be a valid ACM certificate ARN."
  }

  validation {
    condition     = length(flatten([for k, v in var.distributions : v.aliases])) == length(distinct(flatten([for k, v in var.distributions : v.aliases])))
    error_message = "Aliases must be unique across all distributions."
  }
}

################################################################################
# Origins
################################################################################

variable "origins" {
  type = list(object({
    origin_id                = string
    domain_name              = string
    origin_path              = optional(string)
    origin_protocol_policy   = optional(string, "https-only")
    http_port                = optional(number, 80)
    https_port               = optional(number, 443)
    origin_ssl_protocols     = optional(list(string), ["TLSv1.2"])
    origin_keepalive_timeout = optional(number)
    origin_read_timeout      = optional(number)
    origin_access_control_id = optional(string)
    connection_attempts      = optional(number)
    connection_timeout       = optional(number)
    custom_headers = optional(list(object({
      name  = string
      value = string
    })), [])
    origin_shield = optional(object({
      enabled              = bool
      origin_shield_region = string
    }))
    s3_origin = optional(bool, false)
  }))
  description = "A list of origin configurations for the CloudFront distribution."

  validation {
    condition     = length(var.origins) > 0
    error_message = "At least one origin must be specified."
  }

  validation {
    condition     = length(var.origins) == length(distinct([for o in var.origins : o.origin_id]))
    error_message = "All origin_id values must be unique."
  }

  validation {
    condition     = alltrue([for o in var.origins : contains(["http-only", "https-only", "match-viewer"], o.origin_protocol_policy) if !o.s3_origin])
    error_message = "The origin_protocol_policy must be 'http-only', 'https-only', or 'match-viewer'."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.http_port >= 1 && o.http_port <= 65535])
    error_message = "The http_port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.https_port >= 1 && o.https_port <= 65535])
    error_message = "The https_port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.connection_attempts == null || (o.connection_attempts >= 1 && o.connection_attempts <= 3)])
    error_message = "The connection_attempts must be between 1 and 3."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.connection_timeout == null || (o.connection_timeout >= 1 && o.connection_timeout <= 10)])
    error_message = "The connection_timeout must be between 1 and 10 seconds."
  }
}

################################################################################
# Default Cache Behavior
################################################################################

variable "default_cache_behavior" {
  type = object({
    target_origin_id           = string
    viewer_protocol_policy     = string
    allowed_methods            = optional(list(string), ["GET", "HEAD"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compress                   = optional(bool, true)
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    function_associations = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
    lambda_function_associations = optional(list(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool, false)
    })), [])
    realtime_log_config_arn = optional(string)
  })
  description = "The default cache behavior configuration for the CloudFront distribution."

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.default_cache_behavior.viewer_protocol_policy)
    error_message = "The viewer_protocol_policy must be 'allow-all', 'https-only', or 'redirect-to-https'."
  }
}

################################################################################
# Ordered Cache Behaviors
################################################################################

variable "ordered_cache_behaviors" {
  type = list(object({
    path_pattern               = string
    target_origin_id           = string
    viewer_protocol_policy     = string
    allowed_methods            = optional(list(string), ["GET", "HEAD"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compress                   = optional(bool, true)
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    function_associations = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
    lambda_function_associations = optional(list(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool, false)
    })), [])
    realtime_log_config_arn = optional(string)
  }))
  description = "An ordered list of cache behavior configurations. Each must include a path_pattern."
  default     = []

  validation {
    condition     = alltrue([for b in var.ordered_cache_behaviors : contains(["allow-all", "https-only", "redirect-to-https"], b.viewer_protocol_policy)])
    error_message = "The viewer_protocol_policy must be 'allow-all', 'https-only', or 'redirect-to-https'."
  }
}

################################################################################
# Distribution Settings
################################################################################

variable "price_class" {
  type        = string
  description = "The price class for the CloudFront distribution. Controls which edge locations are used."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "The price_class must be 'PriceClass_100', 'PriceClass_200', or 'PriceClass_All'."
  }
}

variable "http_version" {
  type        = string
  description = "The maximum HTTP version to support on the distribution."
  default     = "http2and3"

  validation {
    condition     = contains(["http1.1", "http2", "http2and3"], var.http_version)
    error_message = "The http_version must be 'http1.1', 'http2', or 'http2and3'."
  }
}

variable "is_ipv6_enabled" {
  type        = bool
  description = "Whether IPv6 is enabled for the distribution."
  default     = true
}

variable "default_root_object" {
  type        = string
  description = "The object that CloudFront returns when an end user requests the root URL (e.g., index.html)."
  default     = null
}

variable "retain_on_delete" {
  type        = bool
  description = "Whether to retain the distribution when the resource is deleted (disables instead of deleting)."
  default     = false
}

variable "wait_for_deployment" {
  type        = bool
  description = "Whether to wait for the distribution to be deployed before completing."
  default     = true
}

################################################################################
# SSL/TLS (Viewer Certificate)
################################################################################

variable "minimum_protocol_version" {
  type        = string
  description = "The minimum SSL/TLS protocol version for HTTPS viewer connections."
  default     = "TLSv1.2_2021"

  validation {
    condition = contains([
      "SSLv3",
      "TLSv1",
      "TLSv1_2016",
      "TLSv1.1_2016",
      "TLSv1.2_2018",
      "TLSv1.2_2019",
      "TLSv1.2_2021",
    ], var.minimum_protocol_version)
    error_message = "The minimum_protocol_version must be a valid CloudFront SSL/TLS protocol version."
  }
}

variable "ssl_support_method" {
  type        = string
  description = "How CloudFront serves HTTPS requests. Only applies when acm_certificate_arn is set."
  default     = "sni-only"

  validation {
    condition     = contains(["sni-only", "vip", "static-ip"], var.ssl_support_method)
    error_message = "The ssl_support_method must be 'sni-only', 'vip', or 'static-ip'."
  }
}

################################################################################
# Restrictions
################################################################################

variable "geo_restriction_type" {
  type        = string
  description = "The type of geo restriction: none, whitelist, or blacklist."
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "The geo_restriction_type must be 'none', 'whitelist', or 'blacklist'."
  }
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "A list of ISO 3166-1-alpha-2 country codes for geo restriction."
  default     = []
}

################################################################################
# Custom Error Responses
################################################################################

variable "custom_error_responses" {
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
  description = "A list of custom error response configurations."
  default     = []

  validation {
    condition     = alltrue([for r in var.custom_error_responses : contains([400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504], r.error_code)])
    error_message = "The error_code must be a valid HTTP error code supported by CloudFront (400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504)."
  }
}

################################################################################
# WAF
################################################################################

variable "web_acl_id" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the distribution. Must be a global (CloudFront) WAF."
  default     = null

  validation {
    condition     = var.web_acl_id == null || can(regex("^arn:aws:wafv2:", var.web_acl_id))
    error_message = "The web_acl_id must be a valid WAFv2 Web ACL ARN."
  }
}

################################################################################
# Logging
################################################################################

variable "enable_logging" {
  type        = bool
  description = "Enable access logging for the CloudFront distribution."
  default     = false
}

variable "logging_bucket_domain_name" {
  type        = string
  description = "The domain name of an existing S3 bucket for access logs (e.g., mybucket.s3.amazonaws.com)."
  default     = null
}

variable "logging_prefix" {
  type        = string
  description = "The S3 key prefix for access log files."
  default     = ""
}

variable "logging_include_cookies" {
  type        = bool
  description = "Whether to include cookies in access logs."
  default     = false
}

variable "create_logging_bucket" {
  type        = bool
  description = "Whether to create a new S3 bucket for access logging."
  default     = false
}

variable "logging_bucket_retention_days" {
  type        = number
  description = "The number of days to retain access logs in the logging bucket."
  default     = 90

  validation {
    condition     = var.logging_bucket_retention_days >= 1
    error_message = "The logging_bucket_retention_days must be at least 1."
  }
}

################################################################################
# Origin Access Control
################################################################################

variable "create_origin_access_control" {
  type        = bool
  description = "Whether to create Origin Access Control resources for S3 origins."
  default     = true
}

variable "origin_access_control_origin_type" {
  type        = string
  description = "The type of origin for the Origin Access Control."
  default     = "s3"

  validation {
    condition     = contains(["s3", "mediastore", "mediapackagev2", "lambda"], var.origin_access_control_origin_type)
    error_message = "The origin_access_control_origin_type must be 's3', 'mediastore', 'mediapackagev2', or 'lambda'."
  }
}

variable "origin_access_control_signing_behavior" {
  type        = string
  description = "The signing behavior for the Origin Access Control."
  default     = "always"

  validation {
    condition     = contains(["always", "never", "no-override"], var.origin_access_control_signing_behavior)
    error_message = "The origin_access_control_signing_behavior must be 'always', 'never', or 'no-override'."
  }
}

variable "origin_access_control_signing_protocol" {
  type        = string
  description = "The signing protocol for the Origin Access Control."
  default     = "sigv4"

  validation {
    condition     = var.origin_access_control_signing_protocol == "sigv4"
    error_message = "The origin_access_control_signing_protocol must be 'sigv4'."
  }
}
