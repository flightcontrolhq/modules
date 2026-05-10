################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster Karpenter is managing nodes for. Used to scope IAM permissions and tag interruption events."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster_name must not be empty."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# Controller (Pod Identity)
################################################################################

variable "controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the Karpenter controller runs."
  default     = "kube-system"
}

variable "controller_service_account" {
  type        = string
  description = "Kubernetes service account name for the Karpenter controller."
  default     = "karpenter"
}

################################################################################
# Node Role
################################################################################

variable "node_role_additional_managed_policy_arns" {
  type        = list(string)
  description = "Extra managed policy ARNs to attach to the Karpenter-launched node role."
  default     = []
}

################################################################################
# Interruption Queue
################################################################################

variable "interruption_queue_name" {
  type        = string
  description = "Name for the SQS interruption queue. When null, defaults to 'karpenter-<cluster_name>'."
  default     = null

  validation {
    condition     = var.interruption_queue_name == null || can(regex("^[A-Za-z0-9_-]{1,80}$", var.interruption_queue_name))
    error_message = "The interruption_queue_name must be 1-80 characters of alphanumerics, hyphens, and underscores."
  }
}

variable "interruption_queue_message_retention_seconds" {
  type        = number
  description = "Message retention for the interruption queue. AWS-recommended default is 300s — interruption events are short-lived."
  default     = 300

  validation {
    condition     = var.interruption_queue_message_retention_seconds >= 60 && var.interruption_queue_message_retention_seconds <= 1209600
    error_message = "The retention must be between 60 and 1209600 seconds (SQS limits)."
  }
}
