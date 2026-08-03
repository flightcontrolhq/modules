################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "The name of the customer-managed IAM policy."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "The name must contain 1-128 letters, numbers, plus, equals, comma, period, at, underscore, or hyphen characters."
  }
}

variable "description" {
  type        = string
  description = "The description of the customer-managed IAM policy. AWS does not allow this description to be changed after creation."
  default     = null

  validation {
    condition     = var.description == null || length(var.description) <= 1000
    error_message = "The description must be 1000 characters or fewer."
  }
}

variable "path" {
  type        = string
  description = "The path for the customer-managed IAM policy."
  default     = "/"

  validation {
    condition     = length(var.path) <= 512 && !strcontains(var.path, "*") && (var.path == "/" || can(regex("^/.*/$", var.path)))
    error_message = "The path must be 512 characters or fewer, start and end with '/', and not contain '*'."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the IAM policy."
  default     = {}
}

################################################################################
# Policy Document
################################################################################

variable "policy_statements" {
  type = list(object({
    sid           = optional(string)
    effect        = optional(string, "Allow")
    actions       = optional(list(string), [])
    not_actions   = optional(list(string), [])
    resources     = optional(list(string), [])
    not_resources = optional(list(string), [])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = "Structured IAM policy statements. Ignored when policy_json is provided."
  default     = []

  validation {
    condition = alltrue([
      for statement in var.policy_statements : (
        contains(["Allow", "Deny"], statement.effect) &&
        ((length(statement.actions) > 0) != (length(statement.not_actions) > 0)) &&
        ((length(statement.resources) > 0) != (length(statement.not_resources) > 0)) &&
        alltrue([for condition in statement.conditions : length(condition.values) > 0])
      )
    ])
    error_message = "Each policy statement must use Allow or Deny, set exactly one of actions or not_actions, set exactly one of resources or not_resources, and include at least one value per condition."
  }
}

variable "policy_json" {
  type        = string
  description = "A complete IAM policy JSON document. When provided, this overrides policy_statements."
  default     = null

  validation {
    condition     = var.policy_json == null || (can(jsondecode(var.policy_json)) && can(jsondecode(var.policy_json).Statement))
    error_message = "The policy_json must be valid JSON with a Statement property."
  }
}

variable "region" {
  type        = string
  description = "AWS region used to configure the provider. IAM resources are global. When null, the provider's configured region is used."
  default     = null
}
