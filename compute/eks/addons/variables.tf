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
# AWS Load Balancer Controller
################################################################################

variable "lb_controller_enabled" {
  type        = bool
  description = "Install the AWS Load Balancer Controller even when no shared load balancer is enabled, e.g. to provision ALBs/NLBs directly from Ingress and LoadBalancer resources. The controller is installed automatically whenever any shared load balancer is enabled, since workload target registration (TargetGroupBinding) depends on it."
  default     = false
}

variable "lb_controller_chart_version" {
  type        = string
  description = "Version of the aws-load-balancer-controller Helm chart to install."
  default     = "1.14.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.lb_controller_chart_version))
    error_message = "The lb_controller_chart_version must be a semantic version like '1.14.0' (no leading 'v')."
  }
}

variable "lb_controller_namespace" {
  type        = string
  description = "Namespace the controller is installed into. Must match the Pod Identity association created by the compute/eks stack."
  default     = "kube-system"
}

variable "lb_controller_service_account" {
  type        = string
  description = "Service account name for the controller. Must match the Pod Identity association created by the compute/eks stack."
  default     = "aws-load-balancer-controller"
}

variable "lb_controller_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the aws-load-balancer-controller chart values (later entries win)."
  default     = []
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
# External Secrets Operator
################################################################################

variable "eso_enabled" {
  type        = bool
  description = "Install the External Secrets Operator, its Pod Identity role, and the Ravion ClusterSecretStores. Workloads then reference Secrets Manager secrets and SSM parameters by ARN and ESO materializes them into Kubernetes Secrets, so secret values never pass through Ravion, Helm values, or release history."
  default     = true
}

variable "eso_chart_version" {
  type        = string
  description = "Version of the external-secrets Helm chart to install."
  default     = "2.8.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.eso_chart_version))
    error_message = "The eso_chart_version must be a semantic version like '2.8.0' (no leading 'v')."
  }
}

variable "eso_namespace" {
  type        = string
  description = "Kubernetes namespace the External Secrets Operator is installed into. Created if it does not exist."
  default     = "external-secrets"
  nullable    = false
}

variable "eso_service_account" {
  type        = string
  description = "Service account name for the External Secrets Operator controller. Must match the chart's service account, since the Pod Identity association binds credentials to this name."
  default     = "external-secrets"
  nullable    = false
}

variable "eso_secret_arns" {
  type        = list(string)
  description = "Secrets Manager secret and SSM parameter ARNs (wildcards allowed) the operator may read. When empty, the role can read every secret and parameter in this account and region. Set this to scope the role down, or to grant access to other regions and accounts."
  default     = []

  validation {
    condition     = alltrue([for arn in var.eso_secret_arns : can(regex("^arn:[^:]*:(secretsmanager|ssm):", arn))])
    error_message = "All eso_secret_arns must be Secrets Manager or SSM ARNs, e.g. 'arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/*' or 'arn:aws:ssm:us-east-2:111122223333:parameter/prod/*'."
  }
}

variable "eso_kms_key_arns" {
  type        = list(string)
  description = "Customer-managed KMS key ARNs the operator may decrypt with. Only needed for secrets or parameters encrypted with a customer-managed key; the AWS-managed aws/secretsmanager and aws/ssm keys need no explicit grant."
  default     = []

  validation {
    condition     = alltrue([for arn in var.eso_kms_key_arns : can(regex("^arn:[^:]*:kms:", arn))])
    error_message = "All eso_kms_key_arns must be valid KMS key ARNs."
  }
}

variable "eso_cluster_secret_stores_enabled" {
  type        = bool
  description = "Create the Ravion ClusterSecretStores. Disable to manage SecretStore resources yourself; workload charts then need their own store reference."
  default     = true
}

variable "eso_secrets_manager_store_name" {
  type        = string
  description = "Name of the cluster-scoped AWS Secrets Manager store. This is the store name Ravion app charts default to."
  default     = "ravion-aws"
  nullable    = false
}

variable "eso_parameter_store_store_name" {
  type        = string
  description = "Name of the cluster-scoped AWS SSM Parameter Store store. A separate store is required because ESO's AWS provider takes a single service per store."
  default     = "ravion-aws-parameter-store"
  nullable    = false
}

variable "eso_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the external-secrets chart values, after the values this module derives (CRD install, service account). Later entries win."
  default     = []
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
  description = "Private subnet IDs (node_subnet_ids output of the compute/eks stack). Used by the default Karpenter NodePool to launch nodes and by internal load balancers. Required when Karpenter's default NodePool, the private ALB, or the private NLB is enabled."
  default     = null

  validation {
    condition     = var.node_subnet_ids == null || alltrue([for s in coalesce(var.node_subnet_ids, []) : can(regex("^subnet-", s))])
    error_message = "All node_subnet_ids must start with 'subnet-'."
  }

  validation {
    condition     = !(var.karpenter_enabled && var.karpenter_default_node_pool_enabled) || (var.node_subnet_ids != null && length(coalesce(var.node_subnet_ids, [])) >= 1)
    error_message = "node_subnet_ids is required when karpenter_enabled and karpenter_default_node_pool_enabled are true."
  }

  validation {
    condition     = !(var.private_alb_enabled || var.private_nlb_enabled) || (var.node_subnet_ids != null && length(coalesce(var.node_subnet_ids, [])) >= 1)
    error_message = "node_subnet_ids is required when private_alb_enabled or private_nlb_enabled is true."
  }
}

variable "cluster_security_group_id" {
  type        = string
  description = "EKS-managed cluster security group (cluster_security_group_id output of the compute/eks stack). Attached to Karpenter-launched nodes and opened to shared load balancers so they can reach pods. Required when Karpenter's default NodePool or any shared load balancer is enabled."
  default     = null

  validation {
    condition     = var.cluster_security_group_id == null || can(regex("^sg-", var.cluster_security_group_id))
    error_message = "The cluster_security_group_id must be a valid security group ID starting with 'sg-'."
  }

  validation {
    condition     = !(var.karpenter_enabled && var.karpenter_default_node_pool_enabled) || var.cluster_security_group_id != null
    error_message = "cluster_security_group_id is required when karpenter_enabled and karpenter_default_node_pool_enabled are true."
  }

  validation {
    condition     = !(var.public_alb_enabled || var.private_alb_enabled || var.public_nlb_enabled || var.private_nlb_enabled) || var.cluster_security_group_id != null
    error_message = "cluster_security_group_id is required when any shared load balancer is enabled."
  }
}

################################################################################
# Shared Load Balancers
################################################################################

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for internet-facing load balancers (public_subnet_ids output of the compute/eks stack). Required when the public ALB or public NLB is enabled."
  default     = []

  validation {
    condition     = alltrue([for s in var.public_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All public_subnet_ids must start with 'subnet-'."
  }

  validation {
    condition     = !(var.public_alb_enabled || var.public_nlb_enabled) || length(var.public_subnet_ids) >= 1
    error_message = "public_subnet_ids is required when public_alb_enabled or public_nlb_enabled is true."
  }
}

variable "load_balancer_deletion_protection_enabled" {
  type        = bool
  description = "Enable deletion protection on the shared load balancers."
  default     = false
}

################################################################################
# Public ALB
################################################################################

variable "public_alb_enabled" {
  type        = bool
  description = "Create a shared public (internet-facing) Application Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "public_alb_https_enabled" {
  type        = bool
  description = "Enable HTTPS listener on the public ALB."
  default     = false
}

variable "public_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the public ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.public_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All public_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "public_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the public ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "public_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the public ALB in seconds."
  default     = 60

  validation {
    condition     = var.public_alb_idle_timeout >= 1 && var.public_alb_idle_timeout <= 4000
    error_message = "The public_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "public_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the public ALB."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.public_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All public_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "public_alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access the public ALB."
  default     = ["::/0"]
}

variable "public_alb_ingress_security_group_ids" {
  type        = list(string)
  description = "Security group IDs whose members are allowed to access the public ALB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_alb_ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_alb_ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_alb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the public ALB."
  default     = false
}

variable "public_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public ALB access logs."
  default     = null

  validation {
    condition     = var.public_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_alb_access_logs_bucket_arn))
    error_message = "The public_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_alb_web_acl_arn" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the public ALB."
  default     = null

  validation {
    condition     = var.public_alb_web_acl_arn == null || can(regex("^arn:aws:wafv2:", var.public_alb_web_acl_arn))
    error_message = "The public_alb_web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }
}

################################################################################
# Private ALB
################################################################################

variable "private_alb_enabled" {
  type        = bool
  description = "Create a shared private (internal) Application Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "private_alb_https_enabled" {
  type        = bool
  description = "Enable HTTPS listener on the private ALB."
  default     = false
}

variable "private_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the private ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.private_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All private_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "private_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the private ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "private_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the private ALB in seconds."
  default     = 60

  validation {
    condition     = var.private_alb_idle_timeout >= 1 && var.private_alb_idle_timeout <= 4000
    error_message = "The private_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "private_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the private ALB."
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.private_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All private_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "private_alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access the private ALB. Defaults to no IPv6 ingress; RFC1918 has no IPv6 equivalent."
  default     = []
}

variable "private_alb_ingress_security_group_ids" {
  type        = list(string)
  description = "Security group IDs whose members are allowed to access the private ALB. Useful for sources without static CIDRs, such as CloudFront VPC origins."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_alb_ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_alb_ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_alb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the private ALB."
  default     = false
}

variable "private_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private ALB access logs."
  default     = null

  validation {
    condition     = var.private_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_alb_access_logs_bucket_arn))
    error_message = "The private_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

################################################################################
# Public NLB
################################################################################

variable "public_nlb_enabled" {
  type        = bool
  description = "Create a shared public (internet-facing) Network Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "public_nlb_cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing for the public NLB."
  default     = false
}

variable "public_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of additional security group IDs to attach to the public NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_nlb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the public NLB."
  default     = false
}

variable "public_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public NLB access logs."
  default     = null

  validation {
    condition     = var.public_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_nlb_access_logs_bucket_arn))
    error_message = "The public_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_nlb_elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the public NLB using Elastic IPs."
  default     = false
}

variable "public_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the public NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.public_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All public_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Private NLB
################################################################################

variable "private_nlb_enabled" {
  type        = bool
  description = "Create a shared private (internal) Network Load Balancer that workloads attach to via TargetGroupBinding."
  default     = false
}

variable "private_nlb_cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing for the private NLB."
  default     = false
}

variable "private_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of additional security group IDs to attach to the private NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_nlb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the private NLB."
  default     = false
}

variable "private_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private NLB access logs."
  default     = null

  validation {
    condition     = var.private_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_nlb_access_logs_bucket_arn))
    error_message = "The private_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "private_nlb_elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the private NLB using Elastic IPs."
  default     = false
}

variable "private_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the private NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.private_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All private_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
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

################################################################################
# Ravion Beacon
################################################################################

variable "beacon_enabled" {
  type        = bool
  description = "Install the Ravion Beacon agent: enroll the cluster with the Ravion control plane, store the returned WorkOS Connect M2M credential in AWS Secrets Manager and in a Kubernetes Secret, and install the agent's Helm chart. Beacon dials Ravion outbound over a single WebSocket and is read-only unless beacon_deploy_enabled, beacon_exec_enabled, or the equivalent chart values are turned on."
  default     = false
  nullable    = false
}

variable "beacon_api_url" {
  type        = string
  description = "Base URL of the Ravion API that serves the internal enrollment endpoints, without a trailing slash. The module appends '/internal/beacon/agents'. Same value as the runner's RVN_API_URL, e.g. 'https://api.ravion.com/api/v1'. Required when beacon_enabled is true."
  default     = null

  validation {
    condition     = var.beacon_api_url == null || can(regex("^https?://[^/].*[^/]$", var.beacon_api_url))
    error_message = "The beacon_api_url must be an http(s) URL with no trailing slash, e.g. 'https://api.ravion.com/api/v1'."
  }
}

variable "beacon_api_token" {
  type        = string
  description = "Runner JWT bearer token authenticating the enrollment call. The organization the cluster is enrolled into is taken from this token's claims and is never sent in the request body, so a token for one tenant cannot enroll a cluster into another. Never written to state or to outputs; it reaches the enrollment step as provisioner environment only. Required when beacon_enabled is true."
  default     = null
  sensitive   = true
}

variable "beacon_endpoint" {
  type        = string
  description = "WebSocket endpoint the agent dials. Outbound 443 only, and the single destination a customer's egress policy has to allow. A domain of its own on purpose, so that address need not change when Ravion moves agent connections into their own deployment. Override for staging, a self-hosted control plane, or a local gateway over ws://."
  default     = "wss://websockets.ravion.com/beacon/v1/connect"
  nullable    = false

  validation {
    condition     = can(regex("^wss?://", var.beacon_endpoint))
    error_message = "The beacon_endpoint must be a WebSocket URL starting with 'wss://' (or 'ws://' for local testing)."
  }
}

variable "beacon_chart_source" {
  type        = string
  description = "Where the agent's Helm chart comes from. An 'oci://' reference is split into repository and chart name; anything else is treated as a filesystem path to a chart directory, which is how the chart is tested before it is published to ECR Public. Must stay publicly pullable: customer clusters cannot pull from Ravion's private ECR."
  default     = "oci://public.ecr.aws/ravion/beacon"
  nullable    = false

  validation {
    condition     = length(var.beacon_chart_source) > 0
    error_message = "The beacon_chart_source must not be empty."
  }
}

variable "beacon_chart_version" {
  type        = string
  description = "Version of the Beacon Helm chart to install. When null, Helm resolves the latest. This is the CHART version, not the agent version: the two move independently, because the control plane rolls the agent image forward per cluster while Terraform owns the chart release."
  default     = null

  validation {
    condition     = var.beacon_chart_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.beacon_chart_version))
    error_message = "The beacon_chart_version must be a semantic version like '0.2.0' (no leading 'v')."
  }
}

variable "beacon_namespace" {
  type        = string
  description = "Kubernetes namespace the agent and its credential Secret are installed into. Created if it does not exist."
  default     = "ravion-beacon"
  nullable    = false
}

variable "beacon_namespace_scope" {
  type        = list(string)
  description = "Namespaces the agent may observe. Empty (the default) is the whole cluster. Non-empty renders no observation ClusterRole at all — one namespaced Role and RoleBinding per entry instead — so the restriction is enforced by Kubernetes rather than by the agent. A scoped install can read no nodes and no namespaces, so the node count in fleet health is reported as unknown."
  default     = []
  nullable    = false
}

variable "beacon_deploy_enabled" {
  type        = bool
  description = "Let Beacon perform Ravion's Helm upgrades from inside the cluster instead of Ravion reaching in from outside. The widest grant the chart can create: in the namespaces below, the agent can create, update and delete Deployments, Services, Jobs, Ingresses and Secrets. It can never create RBAC objects, namespaces, or anything cluster-scoped. Declining it leaves a fully working agent and deploys continue to run from outside the cluster."
  default     = false
  nullable    = false
}

variable "beacon_deploy_namespaces" {
  type        = list(string)
  description = "Namespaces Beacon may deploy into. Required when beacon_deploy_enabled is true, falling back to beacon_namespace_scope when empty. If both are empty the install fails rather than granting cluster-wide write: there is no 'deploy everywhere' posture, by design."
  default     = []
  nullable    = false
}

variable "beacon_exec_enabled" {
  type        = bool
  description = "Grant a separate ClusterRole allowing 'create' on pods/exec, the only way Beacon can run a command inside a container. Off by default, recorded on the agent at enrollment as well as granted in the cluster, and scoped with beacon_namespace_scope when that is set."
  default     = false
  nullable    = false
}

variable "beacon_self_update_enabled" {
  type        = bool
  description = "Let the control plane roll the agent forward by patching its own Deployment. The only write permission the chart creates by default: a namespaced Role scoped by resourceNames to Beacon's own Deployment. Turning it off pins the agent to whatever this module last applied, and you take on keeping it current — Ravion supports two agent minor versions back."
  default     = true
  nullable    = false
}

variable "beacon_image_tag" {
  type        = string
  description = "Agent image tag to install. When null, the chart's appVersion is used. This is a FLOOR, not a pin: with self-update on, the control plane moves the running version forward from here and Terraform deliberately ignores subsequent changes to it, so an apply after a staged rollout is a no-op rather than a revert. Changing this value after the release exists therefore requires replacing the release."
  default     = null
}

variable "beacon_helm_values" {
  type        = list(string)
  description = "Extra YAML documents merged into the Beacon chart values (later entries win). The route to values this module does not surface directly, e.g. portForward.enabled, helmInventory.enabled, redaction.extraPatterns, image.repository, resources, or tolerations."
  default     = []
  nullable    = false
}

variable "beacon_project_id" {
  type        = string
  description = "Ravion project this cluster belongs to, recorded on the agent at enrollment. Optional; the enrollment endpoint accepts the cluster identity alone."
  default     = null
}

variable "beacon_environment_id" {
  type        = string
  description = "Ravion environment this cluster belongs to, recorded on the agent at enrollment. Optional."
  default     = null
}

variable "beacon_aws_account_id" {
  type        = string
  description = "Ravion AWS account record the cluster lives in, recorded on the agent at enrollment. This is the Ravion record id (awsact_...), not the 12-digit AWS account number. Optional."
  default     = null
}
