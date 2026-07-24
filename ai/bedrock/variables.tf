################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for the CloudWatch log group and IAM role created by this module."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,35}[a-z0-9])?$", var.name))
    error_message = "The name must contain 1-37 lowercase letters, numbers, or hyphens, starting and ending with a letter or number."
  }
}

variable "region" {
  type        = string
  description = "AWS region where Amazon Bedrock is configured. Defaults to the region configured on the aws provider."
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", coalesce(var.region, "us-east-1")))
    error_message = "The region must be a valid AWS region identifier (e.g. us-east-1, eu-west-2, us-gov-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of additional tags to assign to the CloudWatch log group and IAM role."
  default     = {}
}

################################################################################
# Model Invocation Logging
################################################################################

variable "text_data_delivery_enabled" {
  type        = bool
  description = "Include text model invocation inputs and outputs in delivered logs. Logged data can contain sensitive prompts and responses."
  default     = true
}

variable "image_data_delivery_enabled" {
  type        = bool
  description = "Include image model invocation inputs and outputs in delivered logs."
  default     = false
}

variable "embedding_data_delivery_enabled" {
  type        = bool
  description = "Include embedding model invocation inputs and outputs in delivered logs."
  default     = false
}

variable "video_data_delivery_enabled" {
  type        = bool
  description = "Include video model invocation inputs and outputs in delivered logs."
  default     = false
}

################################################################################
# CloudWatch Logs
################################################################################

variable "log_group_name" {
  type        = string
  description = "Name of the CloudWatch log group to create. Defaults to /aws/bedrock/model-invocations/<name>."
  default     = null

  validation {
    condition = (
      var.log_group_name == null ||
      can(regex("^[A-Za-z0-9_./#-]{1,512}$", coalesce(var.log_group_name, "")))
    )
    error_message = "The log_group_name must contain 1-512 valid CloudWatch Logs name characters."
  }
}

variable "log_group_retention_days" {
  type        = number
  description = "Number of days to retain invocation logs in CloudWatch Logs. Use 0 to retain logs indefinitely."
  default     = 90

  validation {
    condition = contains([
      0,
      1,
      3,
      5,
      7,
      14,
      30,
      60,
      90,
      120,
      150,
      180,
      365,
      400,
      545,
      731,
      1096,
      1827,
      2192,
      2557,
      2922,
      3288,
      3653,
    ], var.log_group_retention_days)
    error_message = "The log_group_retention_days must be 0 or a retention period supported by CloudWatch Logs."
  }
}

variable "log_group_kms_key_arn" {
  type        = string
  description = "ARN of an optional customer-managed KMS key used to encrypt the CloudWatch log group. The key policy must allow the regional CloudWatch Logs service."
  default     = null

  validation {
    condition = (
      var.log_group_kms_key_arn == null ||
      can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/[0-9a-fA-F-]+$", coalesce(var.log_group_kms_key_arn, "")))
    )
    error_message = "The log_group_kms_key_arn must be a valid KMS key ARN."
  }
}
