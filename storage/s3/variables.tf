################################################################################
# Input Variables
################################################################################

#-------------------------------------------------------------------------------
# Required Variables
#-------------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the S3 bucket. Must be globally unique and follow AWS S3 bucket naming rules."

  validation {
    condition     = length(var.name) >= 3
    error_message = "Bucket name must be at least 3 characters long."
  }

  validation {
    condition     = length(var.name) <= 63
    error_message = "Bucket name must not exceed 63 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]", var.name))
    error_message = "Bucket name must start with a lowercase letter or number."
  }

  validation {
    condition     = can(regex("[a-z0-9]$", var.name))
    error_message = "Bucket name must end with a lowercase letter or number."
  }

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.name))
    error_message = "Bucket name can only contain lowercase letters, numbers, hyphens, and periods."
  }

  validation {
    condition     = !can(regex("\\.\\.", var.name))
    error_message = "Bucket name must not contain consecutive periods."
  }

  validation {
    condition     = !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.name))
    error_message = "Bucket name must not be formatted as an IP address."
  }
}

#-------------------------------------------------------------------------------
# Bucket Configuration
#-------------------------------------------------------------------------------

variable "force_destroy" {
  type        = bool
  description = "Whether to force destroy the bucket even if it contains objects. Use with caution."
  default     = false
}

#-------------------------------------------------------------------------------
# Tags
#-------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources. These tags will be merged with default module tags."
  default     = {}
}

#-------------------------------------------------------------------------------
# Encryption (placeholders for locals.tf - full implementation in Task 2.4)
#-------------------------------------------------------------------------------

variable "kms_key_id" {
  type        = string
  description = "The AWS KMS key ID to use for server-side encryption. If not specified, SSE-S3 (AES256) encryption is used."
  default     = null
}

#-------------------------------------------------------------------------------
# Lifecycle (placeholders for locals.tf - full implementation in Task 3.1)
#-------------------------------------------------------------------------------

variable "lifecycle_rules" {
  type        = any
  description = "List of lifecycle rule configurations for the bucket. Each rule can include expiration, transitions, and abort incomplete multipart upload settings."
  default     = []
}

#-------------------------------------------------------------------------------
# Bucket Policy (placeholders for locals.tf - full implementation in Task 3.4)
#-------------------------------------------------------------------------------

variable "policy_templates" {
  type        = list(string)
  description = "List of policy template names to apply to the bucket. Available templates: deny_insecure_transport, alb_access_logs, nlb_access_logs, vpc_flow_logs."
  default     = []
}

variable "custom_policy" {
  type        = string
  description = "Custom bucket policy JSON document. If provided alongside policy_templates, policies will be merged."
  default     = null
}
