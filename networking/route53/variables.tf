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

variable "zone_creation_enabled" {
  type        = bool
  description = "If true, create a new Route53 hosted zone. If false, reference an existing zone via zone_id."
  default     = true
}

variable "zone_id" {
  type        = string
  description = "The ID of an existing Route53 hosted zone to manage records in. Required when zone_creation_enabled is false."
  default     = null

  validation {
    condition     = var.zone_id == null || can(regex("^Z[0-9A-Z]+$", var.zone_id))
    error_message = "The zone_id must be a valid Route53 hosted zone ID (e.g. Z1234567890ABC)."
  }
}

variable "name" {
  type        = string
  description = "The fully qualified domain name for the hosted zone (e.g. example.com). Required when zone_creation_enabled is true."
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

variable "record_force_destroy_enabled" {
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

variable "private_zone_enabled" {
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
  type = list(object({
    name            = string
    type            = string
    ttl             = optional(number)
    records         = optional(list(string))
    set_identifier  = optional(string)
    health_check_id = optional(string)
    allow_overwrite = optional(bool, false)

    target_type                            = optional(string, "standard")
    record_value                           = optional(string)
    record_values                          = optional(list(string))
    standard_ttl                           = optional(number)
    alias_name                             = optional(string)
    alias_zone_id                          = optional(string)
    alias_evaluate_target_health           = optional(bool, false)
    routing_policy                         = optional(string, "simple")
    weighted_routing_policy_weight         = optional(number)
    failover_routing_policy_type           = optional(string)
    latency_routing_policy_region          = optional(string)
    geolocation_routing_policy_continent   = optional(string)
    geolocation_routing_policy_country     = optional(string)
    geolocation_routing_policy_subdivision = optional(string)

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
  description = "A list of DNS records to create in the hosted zone. Terraform derives stable resource keys from each record type, name, and optional set identifier."
  default     = []

  validation {
    condition = alltrue([
      for v in var.records :
      contains(["A", "AAAA", "CNAME", "CAA", "MX", "NAPTR", "NS", "PTR", "SOA", "SPF", "SRV", "TXT", "DS"], v.type)
    ])
    error_message = "Each record type must be one of: A, AAAA, CNAME, CAA, MX, NAPTR, NS, PTR, SOA, SPF, SRV, TXT, DS."
  }

  validation {
    condition = alltrue([
      for v in var.records :
      (
        v.alias != null || (v.target_type == "alias" && v.alias_name != null && v.alias_zone_id != null)
        ) != (
        (v.records != null || v.record_value != null || v.record_values != null) &&
        (v.ttl != null || v.standard_ttl != null)
      )
    ])
    error_message = "Each record must have either `alias` set, or both `records` and `ttl` set (but not both)."
  }

  validation {
    condition = alltrue([
      for v in var.records :
      !contains(["CNAME", "SOA"], v.type) || v.records == null || length(v.records) == 1
    ])
    error_message = "CNAME and SOA records must have exactly one record value."
  }

  validation {
    condition = alltrue([
      for v in var.records :
      v.failover_routing_policy == null || contains(["PRIMARY", "SECONDARY"], coalesce(try(v.failover_routing_policy.type, null), "PRIMARY"))
    ])
    error_message = "failover_routing_policy.type must be PRIMARY or SECONDARY."
  }

  validation {
    condition = alltrue(flatten([
      for v in var.records : [
        for value in concat(
          coalesce(v.records, []),
          coalesce(v.record_values, []),
          v.record_value == null ? [] : [v.record_value]
          ) : [
          # ASCII TXT and SPF values are split into 255-byte quoted strings by the module,
          # so only quoted values and values the module passes through are checked here.
          # base64 encoding is used to measure bytes rather than Unicode characters:
          # a base64 string of at most 340 characters encodes at most 255 bytes.
          for chunk in(
            strcontains(value, "\"") ? [for m in regexall("\"([^\"]*)\"", value) : m[0]] :
            contains(["TXT", "SPF"], v.type) && can(regex("^[[:ascii:]]*$", value)) ? [] : [value]
          ) : length(base64encode(chunk)) <= 340
        ]
      ]
    ]))
    error_message = "Each DNS record value must be at most 255 bytes per character string, which is the Route 53 limit. TXT and SPF values that use only ASCII characters are split automatically; otherwise, split the value into quoted strings of at most 255 bytes each, for example \"first-part\" \"second-part\"."
  }

  validation {
    condition = alltrue(flatten([
      for v in var.records : [
        for value in concat(
          coalesce(v.records, []),
          coalesce(v.record_values, []),
          v.record_value == null ? [] : [v.record_value]
          # A value that uses quotes must be a complete sequence of quoted strings, so no
          # unquoted text is silently passed through to Route 53 unchecked.
        ) : !strcontains(value, "\"") || can(regex("^\\s*(\"[^\"]*\"\\s*)+$", value))
      ]
    ]))
    error_message = "A DNS record value that uses double quotes must be written as one or more complete quoted strings with no text outside the quotes, for example \"first-part\" \"second-part\"."
  }

  validation {
    condition = alltrue([
      for v in var.records :
      sum(concat([0], [
        for value in concat(
          coalesce(v.records, []),
          coalesce(v.record_values, []),
          v.record_value == null ? [] : [v.record_value]
        ) : length(base64encode(value)) / 4 * 3 + 1
      ])) <= 65535
    ])
    error_message = "The combined size of all values for a single DNS record must not exceed 65535 bytes, which is the Route 53 limit on the total record data size."
  }

  validation {
    condition = alltrue([
      for v in var.records :
      (
        v.routing_policy == "simple" &&
        v.weighted_routing_policy == null &&
        v.failover_routing_policy == null &&
        v.latency_routing_policy == null &&
        v.geolocation_routing_policy == null &&
        coalesce(v.multivalue_answer_routing_policy, false) != true
      ) || try(length(v.set_identifier) > 0, false)
    ])
    error_message = "set_identifier is required when using weighted, failover, latency, geolocation, or multivalue routing policies."
  }
}

################################################################################
# Query Logging
################################################################################

variable "query_logging_enabled" {
  type        = bool
  description = "Enable query logging for the hosted zone. Requires a CloudWatch log group ARN in us-east-1 for public zones."
  default     = false
}

variable "query_log_group_creation_enabled" {
  type        = bool
  description = "If true, create a CloudWatch Logs log group and Route53 resource policy in us-east-1 for query logs."
  default     = true
}

variable "query_log_group_name" {
  type        = string
  description = "Name for the created CloudWatch Logs log group. Defaults to /aws/route53/<hosted-zone-name>."
  default     = null

  validation {
    condition     = var.query_log_group_name == null || length(var.query_log_group_name) > 0
    error_message = "The query_log_group_name must not be empty."
  }
}

variable "query_log_group_retention_days" {
  type        = number
  description = "Number of days to retain query logs. Use 0 to retain logs indefinitely."
  default     = 90

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 180, 365, 731, 1827, 3653], var.query_log_group_retention_days)
    error_message = "The query_log_group_retention_days must be 0, 1, 3, 5, 7, 14, 30, 60, 90, 180, 365, 731, 1827, or 3653."
  }
}

variable "query_log_resource_policy_name" {
  type        = string
  description = "Name for the CloudWatch Logs resource policy that allows Route53 to write query logs. Defaults to a hosted-zone-derived name."
  default     = null

  validation {
    condition     = var.query_log_resource_policy_name == null || length(var.query_log_resource_policy_name) > 0
    error_message = "The query_log_resource_policy_name must not be empty."
  }
}

variable "query_log_group_arn" {
  type        = string
  description = "The ARN of an existing CloudWatch log group to stream Route53 query logs to. Required when query_logging_enabled is true."
  default     = null

  validation {
    condition     = var.query_log_group_arn == null || can(regex("^arn:aws:logs:", var.query_log_group_arn))
    error_message = "The query_log_group_arn must be a valid CloudWatch log group ARN."
  }
}

################################################################################
# DNSSEC
################################################################################

variable "dnssec_enabled" {
  type        = bool
  description = "Enable DNSSEC signing for the hosted zone. Requires dnssec_kms_key_arn (a KMS key in us-east-1 with the correct key policy)."
  default     = false
}

variable "dnssec_kms_key_arn" {
  type        = string
  description = "The ARN of a customer-managed KMS key used for DNSSEC signing. The key must be in us-east-1. Required when dnssec_enabled is true."
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

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
