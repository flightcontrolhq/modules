################################################################################
# General
################################################################################

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the hosted zone."
  default     = {}
}

################################################################################
# Hosted Zone
################################################################################

variable "create_zone" {
  type        = bool
  description = "If true, create a new Route53 hosted zone. If false, reference an existing zone via zone_id."
  default     = true
}

variable "zone_id" {
  type        = string
  description = "The ID of an existing Route53 hosted zone to manage records in. Required when create_zone is false."
  default     = null

  validation {
    condition     = var.zone_id == null || can(regex("^Z[0-9A-Z]+$", var.zone_id))
    error_message = "The zone_id must be a valid Route53 hosted zone ID (e.g. Z1234567890ABC)."
  }
}

variable "name" {
  type        = string
  description = "The fully qualified domain name for the hosted zone (e.g. example.com). Required when create_zone is true."
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-._]*[a-zA-Z0-9])?$", var.name))
    error_message = "The name must be a valid domain name."
  }
}

variable "comment" {
  type        = string
  description = "A comment for the hosted zone."
  default     = "Managed by Terraform"
}

variable "force_destroy" {
  type        = bool
  description = "If true, destroy all records in the hosted zone when the zone is destroyed. Only applies to created zones."
  default     = false
}

variable "delegation_set_id" {
  type        = string
  description = "The ID of a reusable delegation set to use for the hosted zone. Only applies to public zones."
  default     = null
}

################################################################################
# Private Zone
################################################################################

variable "private_zone" {
  type        = bool
  description = "If true, the created hosted zone is private and must be associated with one or more VPCs."
  default     = false
}

variable "vpc_associations" {
  type = map(object({
    vpc_id     = string
    vpc_region = optional(string)
  }))
  description = "A map of VPCs to associate with a private hosted zone, keyed by a stable identifier."
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.vpc_associations) : can(regex("^vpc-", v.vpc_id))])
    error_message = "All vpc_associations[*].vpc_id values must be valid VPC IDs starting with 'vpc-'."
  }
}

################################################################################
# DNS Records
################################################################################

variable "records" {
  type = map(object({
    name            = string
    type            = string
    ttl             = optional(number)
    records         = optional(list(string))
    set_identifier  = optional(string)
    health_check_id = optional(string)
    allow_overwrite = optional(bool, false)

    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = optional(bool, false)
    }))

    weighted_routing_policy = optional(object({
      weight = number
    }))

    failover_routing_policy = optional(object({
      type = string
    }))

    latency_routing_policy = optional(object({
      region = string
    }))

    geolocation_routing_policy = optional(object({
      continent   = optional(string)
      country     = optional(string)
      subdivision = optional(string)
    }))

    multivalue_answer_routing_policy = optional(bool)
  }))
  description = "A map of DNS records to create in the hosted zone, keyed by a unique identifier. Each record must have either `records` + `ttl` or `alias` set."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.records :
      contains(["A", "AAAA", "CNAME", "CAA", "MX", "NAPTR", "NS", "PTR", "SOA", "SPF", "SRV", "TXT", "DS"], v.type)
    ])
    error_message = "Each record type must be one of: A, AAAA, CNAME, CAA, MX, NAPTR, NS, PTR, SOA, SPF, SRV, TXT, DS."
  }

  validation {
    condition = alltrue([
      for k, v in var.records :
      (v.alias != null) != (v.records != null && v.ttl != null)
    ])
    error_message = "Each record must have either `alias` set, or both `records` and `ttl` set (but not both)."
  }

  validation {
    condition = alltrue([
      for k, v in var.records :
      v.failover_routing_policy == null || contains(["PRIMARY", "SECONDARY"], coalesce(try(v.failover_routing_policy.type, null), "PRIMARY"))
    ])
    error_message = "failover_routing_policy.type must be PRIMARY or SECONDARY."
  }
}

################################################################################
# Query Logging
################################################################################

variable "enable_query_logging" {
  type        = bool
  description = "Enable query logging for the hosted zone. Requires a CloudWatch log group ARN in us-east-1 for public zones."
  default     = false
}

variable "query_log_group_arn" {
  type        = string
  description = "The ARN of an existing CloudWatch log group to stream Route53 query logs to. Required when enable_query_logging is true."
  default     = null

  validation {
    condition     = var.query_log_group_arn == null || can(regex("^arn:aws:logs:", var.query_log_group_arn))
    error_message = "The query_log_group_arn must be a valid CloudWatch log group ARN."
  }
}

################################################################################
# DNSSEC
################################################################################

variable "enable_dnssec" {
  type        = bool
  description = "Enable DNSSEC signing for the hosted zone. Requires dnssec_kms_key_arn (a KMS key in us-east-1 with the correct key policy)."
  default     = false
}

variable "dnssec_kms_key_arn" {
  type        = string
  description = "The ARN of a customer-managed KMS key used for DNSSEC signing. The key must be in us-east-1. Required when enable_dnssec is true."
  default     = null

  validation {
    condition     = var.dnssec_kms_key_arn == null || can(regex("^arn:aws:kms:us-east-1:", var.dnssec_kms_key_arn))
    error_message = "The dnssec_kms_key_arn must be a valid KMS key ARN in us-east-1."
  }
}

variable "dnssec_signing_status" {
  type        = string
  description = "Signing status for DNSSEC. One of SIGNING or NOT_SIGNING."
  default     = "SIGNING"

  validation {
    condition     = contains(["SIGNING", "NOT_SIGNING"], var.dnssec_signing_status)
    error_message = "The dnssec_signing_status must be SIGNING or NOT_SIGNING."
  }
}
