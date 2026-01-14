################################################################################
# Input Variables
################################################################################

#-------------------------------------------------------------------------------
# Required Variables
#-------------------------------------------------------------------------------

# Note: The 'name' variable and its comprehensive validation will be added in Task 2.1

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
