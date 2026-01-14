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
# Public Access Block
#-------------------------------------------------------------------------------

variable "block_public_acls" {
  type        = bool
  description = "Whether Amazon S3 should block public ACLs for this bucket. Setting this to true causes the following behavior: PUT Bucket acl and PUT Object acl calls will fail if the specified ACL allows public access, and PUT Object calls will fail if the request includes an object ACL."
  default     = true
}

variable "block_public_policy" {
  type        = bool
  description = "Whether Amazon S3 should block public bucket policies for this bucket. Setting this to true causes Amazon S3 to reject calls to PUT Bucket policy if the specified bucket policy allows public access."
  default     = true
}

variable "ignore_public_acls" {
  type        = bool
  description = "Whether Amazon S3 should ignore public ACLs for this bucket. Setting this to true causes Amazon S3 to ignore public ACLs on this bucket and any objects that it contains."
  default     = true
}

variable "restrict_public_buckets" {
  type        = bool
  description = "Whether Amazon S3 should restrict public bucket policies for this bucket. Setting this to true restricts access to this bucket to only AWS service principals and authorized users within this account if the bucket has a public policy."
  default     = true
}

#-------------------------------------------------------------------------------
# Encryption
#-------------------------------------------------------------------------------

variable "kms_key_id" {
  type        = string
  description = "The AWS KMS key ID or ARN to use for server-side encryption (SSE-KMS). If not specified, SSE-S3 (AES256) encryption is used."
  default     = null
}

variable "bucket_key_enabled" {
  type        = bool
  description = "Whether to enable S3 Bucket Keys for SSE-KMS, which reduces KMS API costs. Only applicable when kms_key_id is provided."
  default     = true
}

#-------------------------------------------------------------------------------
# Versioning
#-------------------------------------------------------------------------------

variable "versioning_enabled" {
  type        = bool
  description = "Whether to enable versioning for the S3 bucket. When enabled, S3 keeps multiple versions of an object in the same bucket."
  default     = false
}

#-------------------------------------------------------------------------------
# Lifecycle Rules
#-------------------------------------------------------------------------------

variable "lifecycle_rules" {
  type = list(object({
    id      = string
    enabled = optional(bool, true)

    # Filter settings (at least one filter is required by AWS)
    prefix = optional(string)
    tags   = optional(map(string))

    # Expiration settings
    expiration = optional(object({
      days                         = optional(number)
      date                         = optional(string)
      expired_object_delete_marker = optional(bool)
    }))

    # Noncurrent version expiration (for versioned buckets)
    noncurrent_version_expiration = optional(object({
      noncurrent_days           = optional(number)
      newer_noncurrent_versions = optional(number)
    }))

    # Transitions to different storage classes
    transitions = optional(list(object({
      days          = optional(number)
      date          = optional(string)
      storage_class = string
    })), [])

    # Noncurrent version transitions
    noncurrent_version_transitions = optional(list(object({
      noncurrent_days           = optional(number)
      newer_noncurrent_versions = optional(number)
      storage_class             = string
    })), [])

    # Abort incomplete multipart uploads
    abort_incomplete_multipart_upload_days = optional(number)
  }))
  description = <<-EOT
    List of lifecycle rule configurations for the bucket. Each rule can include:
    - id: Unique identifier for the rule (required)
    - enabled: Whether the rule is enabled (default: true)
    - prefix: Object key prefix to filter objects (optional)
    - tags: Tags to filter objects (optional)
    - expiration: Settings for expiring current objects
    - noncurrent_version_expiration: Settings for expiring noncurrent versions
    - transitions: List of transitions to different storage classes
    - noncurrent_version_transitions: Transitions for noncurrent versions
    - abort_incomplete_multipart_upload_days: Days after which incomplete multipart uploads are aborted
  EOT
  default     = []

  validation {
    condition     = alltrue([for rule in var.lifecycle_rules : rule.id != null && rule.id != ""])
    error_message = "Each lifecycle rule must have a non-empty 'id'."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      alltrue([
        for transition in coalesce(rule.transitions, []) :
        contains(["GLACIER", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "DEEP_ARCHIVE", "GLACIER_IR"], transition.storage_class)
      ])
    ])
    error_message = "Transition storage_class must be one of: GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      alltrue([
        for transition in coalesce(rule.noncurrent_version_transitions, []) :
        contains(["GLACIER", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "DEEP_ARCHIVE", "GLACIER_IR"], transition.storage_class)
      ])
    ])
    error_message = "Noncurrent version transition storage_class must be one of: GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR."
  }
}

#-------------------------------------------------------------------------------
# Bucket Policy
#-------------------------------------------------------------------------------

variable "policy_templates" {
  type        = list(string)
  description = "List of policy template names to apply to the bucket. Available templates: deny_insecure_transport, alb_access_logs, nlb_access_logs, vpc_flow_logs."
  default     = []

  validation {
    condition = alltrue([
      for template in var.policy_templates :
      contains(["deny_insecure_transport", "alb_access_logs", "nlb_access_logs", "vpc_flow_logs"], template)
    ])
    error_message = "Invalid policy template name. Available templates: deny_insecure_transport, alb_access_logs, nlb_access_logs, vpc_flow_logs."
  }
}

variable "custom_policy" {
  type        = string
  description = "Custom bucket policy JSON document. If provided alongside policy_templates, policies will be merged."
  default     = null

  validation {
    condition     = var.custom_policy == null || can(jsondecode(var.custom_policy))
    error_message = "custom_policy must be valid JSON."
  }
}
