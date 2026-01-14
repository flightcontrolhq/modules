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
