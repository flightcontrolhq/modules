################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the existing EKS cluster to install add-ons onto."

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
# EBS CSI Driver
################################################################################

variable "ebs_csi_driver_enabled" {
  type        = bool
  description = "Install the aws-ebs-csi-driver add-on and create its Pod Identity role so workloads can use EBS-backed persistent volumes."
  default     = false
}

variable "ebs_csi_addon_version" {
  type        = string
  description = "Pinned version for the aws-ebs-csi-driver add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "ebs_csi_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for aws-ebs-csi-driver."
  default     = null
}

################################################################################
# CloudWatch Observability (Container Insights)
################################################################################

variable "cloudwatch_observability_enabled" {
  type        = bool
  description = "Install the amazon-cloudwatch-observability add-on (Container Insights) and create its Pod Identity role. Collects node, pod, and container metrics and ships container logs to CloudWatch."
  default     = true
}

variable "cloudwatch_observability_addon_version" {
  type        = string
  description = "Pinned version for the amazon-cloudwatch-observability add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "cloudwatch_observability_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for amazon-cloudwatch-observability."
  default     = null
}

################################################################################
# Karpenter
################################################################################

variable "karpenter_enabled" {
  type        = bool
  description = "Install Karpenter end to end: controller and node IAM roles, Pod Identity association, instance profile, interruption queue, EventBridge rules, the controller Helm charts, and (optionally) a default NodePool."
  default     = true
}

variable "ravion_runner_role_arn" {
  type        = string
  description = "IAM role assumed by `aws eks get-token` to authenticate to the Kubernetes API (ravion_runner_role_arn output of the compute/eks stack). When null, the identity running Terraform is used directly and must already have cluster access."
  default     = null

  validation {
    condition     = var.ravion_runner_role_arn == null || can(regex("^arn:aws", var.ravion_runner_role_arn))
    error_message = "The ravion_runner_role_arn must be an IAM role ARN starting with 'arn:aws'."
  }
}

variable "karpenter_controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the Karpenter controller is installed."
  default     = "kube-system"
  nullable    = false
}

variable "karpenter_controller_service_account" {
  type        = string
  description = "Kubernetes service account name for the Karpenter controller."
  default     = "karpenter"
  nullable    = false
}

variable "karpenter_node_role_additional_managed_policy_arns" {
  type        = list(string)
  description = "Extra managed policy ARNs to attach to the Karpenter-launched node role."
  default     = []
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
  description = "Name for the SQS interruption queue. When null, defaults to 'karpenter-<cluster_name>'."
  default     = null
}

variable "karpenter_interruption_queue_message_retention_seconds" {
  type        = number
  description = "Message retention for the Karpenter interruption queue."
  default     = 300
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

variable "node_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs the default NodePool launches nodes into (node_subnet_ids output of the compute/eks stack). Required when Karpenter and the default NodePool are enabled."
  default     = null

  validation {
    condition     = var.node_subnet_ids == null || alltrue([for s in coalesce(var.node_subnet_ids, []) : can(regex("^subnet-", s))])
    error_message = "All node_subnet_ids must start with 'subnet-'."
  }

  validation {
    condition     = !(var.karpenter_enabled && var.karpenter_default_node_pool_enabled) || (var.node_subnet_ids != null && length(coalesce(var.node_subnet_ids, [])) >= 1)
    error_message = "node_subnet_ids is required when karpenter_enabled and karpenter_default_node_pool_enabled are true."
  }
}

variable "cluster_security_group_id" {
  type        = string
  description = "EKS-managed cluster security group attached to Karpenter-launched nodes (cluster_security_group_id output of the compute/eks stack). Required when Karpenter and the default NodePool are enabled."
  default     = null

  validation {
    condition     = var.cluster_security_group_id == null || can(regex("^sg-", var.cluster_security_group_id))
    error_message = "The cluster_security_group_id must be a valid security group ID starting with 'sg-'."
  }

  validation {
    condition     = !(var.karpenter_enabled && var.karpenter_default_node_pool_enabled) || var.cluster_security_group_id != null
    error_message = "cluster_security_group_id is required when karpenter_enabled and karpenter_default_node_pool_enabled are true."
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
