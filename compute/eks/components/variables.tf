################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the existing EKS cluster to install components onto."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.cluster_name))
    error_message = "The cluster_name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags applied to EC2 instances launched by the default Karpenter NodePool."
  default     = {}
}

################################################################################
# Karpenter Controller
################################################################################

variable "karpenter_controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the Karpenter controller is installed. Must match the Pod Identity association created by the compute/eks stack."
  default     = "kube-system"
  nullable    = false
}

variable "karpenter_controller_service_account" {
  type        = string
  description = "Kubernetes service account name for the Karpenter controller. Must match the Pod Identity association created by the compute/eks stack."
  default     = "karpenter"
  nullable    = false
}

variable "karpenter_chart_version" {
  type        = string
  description = "Version of the Karpenter Helm chart (and karpenter-crd chart) to install."
  default     = "1.14.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.karpenter_chart_version))
    error_message = "The karpenter_chart_version must be a semantic version like '1.14.0' (no leading 'v')."
  }
}

variable "karpenter_interruption_queue_name" {
  type        = string
  description = "Name of the SQS interruption queue created by the compute/eks stack (karpenter_interruption_queue_name output)."
}

variable "karpenter_helm_values" {
  type        = list(string)
  description = "Additional YAML documents merged into the Karpenter Helm chart values, after the values this module derives (cluster name, interruption queue, service account). Later entries win."
  default     = []
}

################################################################################
# Default NodePool
################################################################################

variable "karpenter_default_node_pool_enabled" {
  type        = bool
  description = "Create a general-purpose default NodePool and EC2NodeClass so Karpenter can provision nodes out of the box. Disable to manage NodePools yourself."
  default     = true
}

variable "karpenter_node_instance_profile_name" {
  type        = string
  description = "IAM instance profile for Karpenter-launched nodes, created by the compute/eks stack (karpenter_node_instance_profile_name output)."
}

variable "node_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs the default NodePool launches nodes into (node_subnet_ids output of the compute/eks stack)."

  validation {
    condition     = length(var.node_subnet_ids) >= 1 && alltrue([for s in var.node_subnet_ids : can(regex("^subnet-", s))])
    error_message = "At least one subnet ID starting with 'subnet-' is required."
  }
}

variable "cluster_security_group_id" {
  type        = string
  description = "EKS-managed cluster security group attached to Karpenter-launched nodes (cluster_security_group_id output of the compute/eks stack)."

  validation {
    condition     = can(regex("^sg-", var.cluster_security_group_id))
    error_message = "The cluster_security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "karpenter_default_node_pool" {
  type = object({
    capacity_types      = optional(list(string), ["on-demand", "spot"])
    instance_categories = optional(list(string), ["c", "m", "r"])
    architectures       = optional(list(string), ["amd64"])
    cpu_limit           = optional(number, 100)
    expire_after        = optional(string, "720h")
  })
  description = "Settings for the default NodePool: allowed capacity types (on-demand/spot), EC2 instance categories, CPU architectures, total vCPU limit, and node expiry."
  default     = {}

  validation {
    condition     = alltrue([for t in var.karpenter_default_node_pool.capacity_types : contains(["on-demand", "spot"], t)])
    error_message = "The karpenter_default_node_pool.capacity_types entries must be 'on-demand' or 'spot'."
  }

  validation {
    condition     = alltrue([for a in var.karpenter_default_node_pool.architectures : contains(["amd64", "arm64"], a)])
    error_message = "The karpenter_default_node_pool.architectures entries must be 'amd64' or 'arm64'."
  }
}
