################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the EKS cluster. Used as the cluster name and as the prefix for related resources."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.name))
    error_message = "The name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the cluster will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the EKS-managed control plane ENIs. Also used as the default node / Fargate placement when node_subnet_ids is null. Typically private subnets in at least two availability zones."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs (in different availability zones) are required for EKS control plane high availability."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "node_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the system node group, additional node groups, and Fargate profiles when they do not override placement. Defaults to subnet_ids."
  default     = null

  validation {
    condition = var.node_subnet_ids == null || (
      length(var.node_subnet_ids) >= 1 &&
      alltrue([for s in var.node_subnet_ids : can(regex("^subnet-", s))])
    )
    error_message = "When set, node_subnet_ids must contain at least one subnet ID starting with 'subnet-'."
  }
}

################################################################################
# Cluster
################################################################################

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use for the EKS cluster. Format: 'X.YY' (e.g. '1.31'). When null, AWS uses the latest supported version."
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The kubernetes_version must be in 'MAJOR.MINOR' form (e.g. '1.31')."
  }
}

variable "public_endpoint_access_enabled" {
  type        = bool
  description = "Whether the EKS API server endpoint is reachable from the public internet."
  default     = false
}

variable "private_endpoint_access_enabled" {
  type        = bool
  description = "Whether the EKS API server endpoint is reachable from inside the VPC."
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public EKS API server endpoint. Only applies when public_endpoint_access_enabled is true."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "All public_access_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "service_ipv4_cidr" {
  type        = string
  description = "Optional CIDR block from which Kubernetes service IPs are assigned. When null, EKS picks a default."
  default     = null

  validation {
    condition     = var.service_ipv4_cidr == null || can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "The service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}

variable "ip_family" {
  type        = string
  description = "IP family for the cluster. Either 'ipv4' or 'ipv6'."
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "The ip_family must be 'ipv4' or 'ipv6'."
  }
}

variable "additional_cluster_security_group_ingress" {
  type = list(object({
    description = optional(string)
    from_port   = number
    to_port     = number
    ip_protocol = string
    cidr_ipv4   = string
  }))
  description = "Extra ingress rules to attach to the EKS-managed cluster security group, sourced by IPv4 CIDR."
  default     = []
}

variable "additional_cluster_security_group_ingress_sg" {
  type = list(object({
    description                  = optional(string)
    from_port                    = number
    to_port                      = number
    ip_protocol                  = string
    referenced_security_group_id = string
  }))
  description = "Extra ingress rules to attach to the EKS-managed cluster security group, sourced by another security group."
  default     = []
}

variable "cluster_creator_admin_permissions_enabled" {
  type        = bool
  description = "Whether to grant the IAM principal that creates the cluster the EKS cluster admin permissions automatically."
  default     = true
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    user_name         = optional(string)
    policy_associations = optional(map(object({
      policy_arn = string
      access_scope = object({
        type       = string
        namespaces = optional(list(string))
      })
    })), {})
  }))
  description = "Map of EKS access entries to create. Map keys are arbitrary stable identifiers."
  default     = {}
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Which control plane log types to ship to CloudWatch Logs. Set to [] to disable cluster logging entirely."
  default     = ["api", "audit", "authenticator"]
}

variable "cluster_log_retention_in_days" {
  type        = number
  description = "Retention (days) for the EKS control plane CloudWatch log group."
  default     = 30
}

variable "secrets_encryption_enabled" {
  type        = bool
  description = "Enable envelope encryption for Kubernetes secrets using KMS."
  default     = true
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "ARN of an existing KMS key for Kubernetes secrets. When null and secrets_encryption_enabled is true, the cluster module creates one."
  default     = null
}

variable "vpc_cni_addon_version" {
  type        = string
  description = "Pinned version for the vpc-cni add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "vpc_cni_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for vpc-cni."
  default     = null
}

variable "kube_proxy_addon_version" {
  type        = string
  description = "Pinned version for the kube-proxy add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "kube_proxy_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for kube-proxy."
  default     = null
}

variable "pod_identity_agent_enabled" {
  type        = bool
  description = "Install the eks-pod-identity-agent add-on."
  default     = true
}

variable "pod_identity_agent_addon_version" {
  type        = string
  description = "Pinned version for the eks-pod-identity-agent add-on."
  default     = null
}

variable "lb_controller_pod_identity_enabled" {
  type        = bool
  description = "Create an IAM role and Pod Identity association for the AWS Load Balancer Controller."
  default     = true
}

variable "lb_controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the AWS Load Balancer Controller's service account lives."
  default     = "kube-system"
}

variable "lb_controller_service_account" {
  type        = string
  description = "Kubernetes service account name used by the AWS Load Balancer Controller."
  default     = "aws-load-balancer-controller"
}

variable "pod_identity_associations" {
  type = map(object({
    namespace       = string
    service_account = string
    role_arn        = string
  }))
  description = "Additional Pod Identity associations to create on the cluster."
  default     = {}
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, the cluster cannot be deleted via the AWS API until this is set to false."
  default     = true
}

################################################################################
# Node Groups
################################################################################

variable "system_node_group" {
  type = object({
    name                         = optional(string, "system")
    capacity_type                = optional(string, "ON_DEMAND")
    instance_types               = optional(list(string), ["t3.medium"])
    ami_type                     = optional(string, "AL2023_x86_64_STANDARD")
    kubernetes_version           = optional(string)
    min_size                     = optional(number, 2)
    desired_size                 = optional(number, 2)
    max_size                     = optional(number, 4)
    max_unavailable              = optional(number)
    max_unavailable_percentage   = optional(number, 33)
    version_force_update_enabled = optional(bool, false)
    labels                       = optional(map(string), { role = "system" })
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    disk_size                                = optional(number)
    disk_type                                = optional(string)
    disk_iops                                = optional(number)
    disk_throughput                          = optional(number)
    ebs_kms_key_arn                          = optional(string)
    user_data                                = optional(string)
    security_group_ids                       = optional(list(string), [])
    detailed_monitoring_enabled              = optional(bool, false)
    metadata_http_tokens                     = optional(string, "required")
    metadata_http_put_response_hop_limit     = optional(number, 2)
    node_role_arn                            = optional(string)
    additional_node_role_managed_policy_arns = optional(list(string), [])
    additional_node_role_inline_policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  description = "Configuration for the required system managed node group that provides compute for Deployment-kind add-ons (CoreDNS, etc.)."
  default     = {}
}

variable "additional_node_groups" {
  type = map(object({
    subnet_ids                   = optional(list(string))
    capacity_type                = optional(string, "ON_DEMAND")
    instance_types               = optional(list(string), ["t3.medium"])
    ami_type                     = optional(string, "AL2023_x86_64_STANDARD")
    kubernetes_version           = optional(string)
    min_size                     = optional(number, 1)
    desired_size                 = optional(number, 1)
    max_size                     = optional(number, 3)
    max_unavailable              = optional(number)
    max_unavailable_percentage   = optional(number, 33)
    version_force_update_enabled = optional(bool, false)
    labels                       = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    disk_size                                = optional(number)
    disk_type                                = optional(string)
    disk_iops                                = optional(number)
    disk_throughput                          = optional(number)
    ebs_kms_key_arn                          = optional(string)
    user_data                                = optional(string)
    security_group_ids                       = optional(list(string), [])
    detailed_monitoring_enabled              = optional(bool, false)
    metadata_http_tokens                     = optional(string, "required")
    metadata_http_put_response_hop_limit     = optional(number, 2)
    node_role_arn                            = optional(string)
    additional_node_role_managed_policy_arns = optional(list(string), [])
    additional_node_role_inline_policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  }))
  description = "Optional additional managed node groups keyed by node group name. Placement defaults to node_subnet_ids (or subnet_ids)."
  default     = {}
}

################################################################################
# Post-compute Add-ons
################################################################################

variable "coredns_addon_version" {
  type        = string
  description = "Pinned version for the coredns add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "coredns_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for coredns."
  default     = null
}

variable "ebs_csi_driver_enabled" {
  type        = bool
  description = "Install the aws-ebs-csi-driver add-on and create its Pod Identity role."
  default     = false
}

variable "ebs_csi_addon_version" {
  type        = string
  description = "Pinned version for the aws-ebs-csi-driver add-on."
  default     = null
}

variable "ebs_csi_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for aws-ebs-csi-driver."
  default     = null
}

################################################################################
# Karpenter
################################################################################

variable "karpenter_enabled" {
  type        = bool
  description = "Provision Karpenter IAM roles, instance profile, interruption queue, and EventBridge rules."
  default     = false
}

variable "karpenter_controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the Karpenter controller runs."
  default     = "kube-system"
}

variable "karpenter_controller_service_account" {
  type        = string
  description = "Kubernetes service account name for the Karpenter controller."
  default     = "karpenter"
}

variable "karpenter_node_role_additional_managed_policy_arns" {
  type        = list(string)
  description = "Extra managed policy ARNs to attach to the Karpenter-launched node role."
  default     = []
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

variable "karpenter_chart_enabled" {
  type        = bool
  description = "Install the Karpenter controller Helm chart into the cluster. Disable to manage the controller out-of-band (e.g. GitOps) while keeping the AWS-side resources from karpenter_enabled."
  default     = true
}

variable "karpenter_chart_version" {
  type        = string
  description = "Version of the Karpenter Helm chart (and karpenter-crd chart) to install."
  default     = "1.14.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.karpenter_chart_version))
    error_message = "The karpenter_chart_version must be a semantic version like '1.14.0' (no leading 'v')."
  }
}

variable "karpenter_helm_values" {
  type        = list(string)
  description = "Additional YAML documents merged into the Karpenter Helm chart values, after the values this module derives (cluster name, interruption queue, service account). Later entries win."
  default     = []
}

variable "karpenter_default_node_pool_enabled" {
  type        = bool
  description = "Create a general-purpose default NodePool and EC2NodeClass so Karpenter can provision nodes out of the box. Disable to manage NodePools yourself."
  default     = true
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

################################################################################
# Fargate
################################################################################

variable "fargate_profiles" {
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
    subnet_ids             = optional(list(string))
    pod_execution_role_arn = optional(string)
  }))
  description = "Optional Fargate profiles keyed by profile name. subnet_ids defaults to node_subnet_ids (or subnet_ids)."
  default     = {}

  validation {
    condition = alltrue([
      for p in values(var.fargate_profiles) : length(p.selectors) >= 1
    ])
    error_message = "Each fargate_profiles entry must include at least one selector."
  }
}
