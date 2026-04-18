################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the Secrets Manager secret."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 512
    error_message = "The name must be between 1 and 512 characters."
  }
}

variable "description" {
  type        = string
  description = "Description for the Secrets Manager secret."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the secret."
  default     = {}
}

################################################################################
# Secret Value
################################################################################

variable "secret_string" {
  type        = string
  description = "The plaintext value to store in the secret. Mutually exclusive with secret_json."
  default     = null
  sensitive   = true
}

variable "secret_json" {
  type        = any
  description = "A map to store in the secret as JSON. Mutually exclusive with secret_string."
  default     = null
  sensitive   = true
}

variable "create_version" {
  type        = bool
  description = "Create an initial secret version from secret_string / secret_json. Disable if the value will be populated out-of-band (e.g., by a rotation lambda)."
  default     = true
}

################################################################################
# Encryption & Lifecycle
################################################################################

variable "kms_key_id" {
  type        = string
  description = "ARN or ID of the KMS key used to encrypt the secret. If not specified, the default AWS managed key is used."
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^(arn:aws(-[a-z]+)?:kms:|[a-f0-9-]{36}$|alias/)", var.kms_key_id))
    error_message = "The kms_key_id must be a KMS key ARN, ID, or alias."
  }
}

variable "recovery_window_in_days" {
  type        = number
  description = "The number of days that Secrets Manager waits before permanently deleting the secret. Set to 0 to force immediate deletion."
  default     = 7

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "The recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "policy" {
  type        = string
  description = "A JSON resource policy document to attach to the secret."
  default     = null
}
