################################################################################
# General
################################################################################

variable "region" {
  type        = string
  description = "AWS region to create the certificate in. Use 'us-east-1' for certificates attached to CloudFront distributions. When null, uses the provider's configured region."
  default     = null
}

variable "name" {
  type        = string
  description = "Name prefix used for tagging the ACM certificate."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 64
    error_message = "The name must be between 1 and 64 characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the ACM certificate."
  default     = {}
}

################################################################################
# Certificate
################################################################################

variable "domains" {
  type        = list(string)
  description = "Ordered FQDNs for the ACM certificate. The first domain is primary and the remaining domains are Subject Alternative Names."

  validation {
    condition = (
      length(var.domains) > 0 &&
      alltrue([for domain in var.domains : length(trimspace(domain)) > 0]) &&
      length(distinct([for domain in var.domains : lower(domain)])) == length(var.domains)
    )
    error_message = "The domains list must contain at least one non-empty, unique domain name."
  }
}

################################################################################
# DNS validation
################################################################################

variable "route53_validation_records_creation_enabled" {
  type        = bool
  description = "If true, create Route53 CNAME records for DNS validation in route53_zone_id."
  default     = false

  validation {
    condition     = !var.route53_validation_records_creation_enabled || var.route53_zone_id != null
    error_message = "route53_zone_id is required when route53_validation_records_creation_enabled is true."
  }
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 public hosted zone ID for validation records. Required when route53_validation_records_creation_enabled is true."
  default     = null

  validation {
    condition     = var.route53_zone_id == null || can(regex("^Z[0-9A-Z]+$", var.route53_zone_id))
    error_message = "The route53_zone_id must be a valid Route53 hosted zone ID (e.g. Z1234567890ABC)."
  }
}

variable "certificate_validation_wait_enabled" {
  type        = bool
  description = "If true, create aws_acm_certificate_validation and wait until the certificate is issued."
  default     = false
}
