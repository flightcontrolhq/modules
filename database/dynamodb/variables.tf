################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the DynamoDB table. Also used as a prefix for related resources (alarms, autoscaling policies)."

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 255 && can(regex("^[a-zA-Z0-9_.-]+$", var.name))
    error_message = "The name must be 3-255 characters and contain only letters, numbers, underscores, hyphens, and dots."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Keys & Attributes
################################################################################

variable "hash_key" {
  type        = string
  description = "Name of the attribute to use as the hash (partition) key. Must be defined in var.attributes."

  validation {
    condition     = length(var.hash_key) > 0
    error_message = "The hash_key must not be empty."
  }
}

variable "range_key" {
  type        = string
  description = "Name of the attribute to use as the range (sort) key. Must be defined in var.attributes if set."
  default     = null
}

variable "attributes" {
  type = list(object({
    name = string
    type = string
  }))
  description = "List of attribute definitions. Each must have name and type (S=String, N=Number, B=Binary). Only attributes referenced by the table or an index should be listed."

  validation {
    condition     = length(var.attributes) >= 1
    error_message = "At least one attribute must be defined."
  }

  validation {
    condition     = alltrue([for a in var.attributes : contains(["S", "N", "B"], a.type)])
    error_message = "Each attribute type must be one of: S, N, B."
  }
}

################################################################################
# Billing & Capacity
################################################################################

variable "billing_mode" {
  type        = string
  description = "Controls how capacity is billed. PAY_PER_REQUEST (on-demand) or PROVISIONED."
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "The billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  type        = number
  description = "Read capacity units for the table. Required and must be >= 1 when billing_mode is PROVISIONED."
  default     = null

  validation {
    condition     = var.read_capacity == null || var.read_capacity >= 1
    error_message = "The read_capacity must be at least 1 when specified."
  }
}

variable "write_capacity" {
  type        = number
  description = "Write capacity units for the table. Required and must be >= 1 when billing_mode is PROVISIONED."
  default     = null

  validation {
    condition     = var.write_capacity == null || var.write_capacity >= 1
    error_message = "The write_capacity must be at least 1 when specified."
  }
}

variable "table_class" {
  type        = string
  description = "The storage class of the table. STANDARD or STANDARD_INFREQUENT_ACCESS."
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "The table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

################################################################################
# Indexes
################################################################################

variable "global_secondary_indexes" {
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  description = "List of global secondary indexes. projection_type must be ALL, KEYS_ONLY, or INCLUDE (INCLUDE requires non_key_attributes)."
  default     = []

  validation {
    condition     = alltrue([for gsi in var.global_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], gsi.projection_type)])
    error_message = "Each global_secondary_indexes projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  }

  validation {
    condition     = alltrue([for gsi in var.global_secondary_indexes : gsi.projection_type != "INCLUDE" || try(length(gsi.non_key_attributes), 0) > 0])
    error_message = "When projection_type is INCLUDE, non_key_attributes must be provided."
  }
}

variable "local_secondary_indexes" {
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string))
  }))
  description = "List of local secondary indexes. Requires var.range_key to be set. projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  default     = []

  validation {
    condition     = alltrue([for lsi in var.local_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], lsi.projection_type)])
    error_message = "Each local_secondary_indexes projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  }

  validation {
    condition     = alltrue([for lsi in var.local_secondary_indexes : lsi.projection_type != "INCLUDE" || try(length(lsi.non_key_attributes), 0) > 0])
    error_message = "When projection_type is INCLUDE, non_key_attributes must be provided."
  }
}

################################################################################
# TTL
################################################################################

variable "ttl_enabled" {
  type        = bool
  description = "Enable Time To Live (TTL) on the table. Requires ttl_attribute_name."
  default     = false
}

variable "ttl_attribute_name" {
  type        = string
  description = "Name of the attribute to use for TTL. Items with this attribute set to a past epoch time will be deleted."
  default     = ""
}

################################################################################
# Streams
################################################################################

variable "stream_enabled" {
  type        = bool
  description = "Enable DynamoDB Streams for the table."
  default     = false
}

variable "stream_view_type" {
  type        = string
  description = "What data is written to the stream. KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, or NEW_AND_OLD_IMAGES."
  default     = "NEW_AND_OLD_IMAGES"

  validation {
    condition     = contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "The stream_view_type must be KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, or NEW_AND_OLD_IMAGES."
  }
}

################################################################################
# Encryption
################################################################################

variable "server_side_encryption_enabled" {
  type        = bool
  description = "Enable server-side encryption. When true with no KMS key ARN, DynamoDB uses an AWS-owned key."
  default     = true
}

variable "server_side_encryption_kms_key_arn" {
  type        = string
  description = "ARN of a customer-managed KMS key for encryption. If null, DynamoDB uses an AWS-owned key."
  default     = null

  validation {
    condition     = var.server_side_encryption_kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)?:kms:", var.server_side_encryption_kms_key_arn))
    error_message = "The server_side_encryption_kms_key_arn must be a valid KMS key ARN."
  }
}

################################################################################
# Recovery & Protection
################################################################################

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Enable point-in-time recovery (continuous backups up to 35 days)."
  default     = true
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "Protect the table from accidental deletion."
  default     = false
}

################################################################################
# Global Tables (v2 replicas)
################################################################################

variable "replicas" {
  type = list(object({
    region_name            = string
    kms_key_arn            = optional(string)
    propagate_tags         = optional(bool, true)
    point_in_time_recovery = optional(bool, true)
  }))
  description = "List of replica regions for a global table (v2). Requires stream_enabled = true."
  default     = []

  validation {
    condition     = alltrue([for r in var.replicas : r.kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)?:kms:", r.kms_key_arn))])
    error_message = "Each replica kms_key_arn must be a valid KMS key ARN when specified."
  }
}

################################################################################
# Autoscaling (Provisioned only)
################################################################################

variable "autoscaling_enabled" {
  type        = bool
  description = "Enable application autoscaling for table read/write capacity. Only applies when billing_mode is PROVISIONED."
  default     = false
}

variable "autoscaling_read" {
  type = object({
    min_capacity       = number
    max_capacity       = number
    target_utilization = optional(number, 70)
    scale_in_cooldown  = optional(number, 60)
    scale_out_cooldown = optional(number, 60)
  })
  description = "Autoscaling configuration for table read capacity."
  default = {
    min_capacity = 5
    max_capacity = 100
  }

  validation {
    condition     = var.autoscaling_read.min_capacity >= 1 && var.autoscaling_read.max_capacity >= var.autoscaling_read.min_capacity
    error_message = "autoscaling_read.min_capacity must be >= 1 and max_capacity must be >= min_capacity."
  }

  validation {
    condition     = var.autoscaling_read.target_utilization == null || (var.autoscaling_read.target_utilization > 0 && var.autoscaling_read.target_utilization <= 100)
    error_message = "autoscaling_read.target_utilization must be between 1 and 100."
  }
}

variable "autoscaling_write" {
  type = object({
    min_capacity       = number
    max_capacity       = number
    target_utilization = optional(number, 70)
    scale_in_cooldown  = optional(number, 60)
    scale_out_cooldown = optional(number, 60)
  })
  description = "Autoscaling configuration for table write capacity."
  default = {
    min_capacity = 5
    max_capacity = 100
  }

  validation {
    condition     = var.autoscaling_write.min_capacity >= 1 && var.autoscaling_write.max_capacity >= var.autoscaling_write.min_capacity
    error_message = "autoscaling_write.min_capacity must be >= 1 and max_capacity must be >= min_capacity."
  }

  validation {
    condition     = var.autoscaling_write.target_utilization == null || (var.autoscaling_write.target_utilization > 0 && var.autoscaling_write.target_utilization <= 100)
    error_message = "autoscaling_write.target_utilization must be between 1 and 100."
  }
}

variable "autoscaling_indexes" {
  type = map(object({
    read = optional(object({
      min_capacity       = number
      max_capacity       = number
      target_utilization = optional(number, 70)
      scale_in_cooldown  = optional(number, 60)
      scale_out_cooldown = optional(number, 60)
    }))
    write = optional(object({
      min_capacity       = number
      max_capacity       = number
      target_utilization = optional(number, 70)
      scale_in_cooldown  = optional(number, 60)
      scale_out_cooldown = optional(number, 60)
    }))
  }))
  description = "Per-GSI autoscaling configuration, keyed by GSI name. Omit an index key to skip autoscaling for it; omit read or write to skip that dimension."
  default     = {}
}

################################################################################
# CloudWatch Alarms
################################################################################

variable "create_cloudwatch_alarms" {
  type        = bool
  description = "Create CloudWatch alarms for throttled requests and system errors."
  default     = false
}

variable "cloudwatch_alarm_actions" {
  type        = list(string)
  description = "List of ARNs notified when alarms transition to ALARM state (e.g., SNS topics)."
  default     = []
}

variable "cloudwatch_ok_actions" {
  type        = list(string)
  description = "List of ARNs notified when alarms transition to OK state."
  default     = []
}

variable "cloudwatch_alarm_evaluation_periods" {
  type        = number
  description = "Number of periods over which data is compared to the threshold."
  default     = 2

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "The cloudwatch_alarm_evaluation_periods must be at least 1."
  }
}

variable "cloudwatch_alarm_period" {
  type        = number
  description = "The period in seconds over which the statistic is applied."
  default     = 300

  validation {
    condition     = contains([10, 30, 60, 300, 900, 3600], var.cloudwatch_alarm_period)
    error_message = "The cloudwatch_alarm_period must be one of: 10, 30, 60, 300, 900, or 3600 seconds."
  }
}

variable "cloudwatch_read_throttle_threshold" {
  type        = number
  description = "Threshold for the ReadThrottleEvents alarm."
  default     = 10

  validation {
    condition     = var.cloudwatch_read_throttle_threshold >= 0
    error_message = "The cloudwatch_read_throttle_threshold must be at least 0."
  }
}

variable "cloudwatch_write_throttle_threshold" {
  type        = number
  description = "Threshold for the WriteThrottleEvents alarm."
  default     = 10

  validation {
    condition     = var.cloudwatch_write_throttle_threshold >= 0
    error_message = "The cloudwatch_write_throttle_threshold must be at least 0."
  }
}

variable "cloudwatch_system_errors_threshold" {
  type        = number
  description = "Threshold for the SystemErrors alarm."
  default     = 5

  validation {
    condition     = var.cloudwatch_system_errors_threshold >= 0
    error_message = "The cloudwatch_system_errors_threshold must be at least 0."
  }
}

################################################################################
# Timeouts
################################################################################

variable "timeouts" {
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  description = "Custom timeouts for create, update, and delete operations (e.g., \"30m\")."
  default     = {}
}
