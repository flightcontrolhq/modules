################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name for the ECS service and related resources."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "The name must be between 1 and 255 characters."
  }
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
  description = "The ID of the VPC where the ECS service will run."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the ECS service tasks."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "assign_public_ip" {
  type        = bool
  description = "Assign a public IP address to the ECS tasks. Required for Fargate tasks in public subnets without NAT."
  default     = false
}

################################################################################
# ECS Cluster
################################################################################

variable "cluster_arn" {
  type        = string
  description = "The ARN of the ECS cluster where the service will be deployed."

  validation {
    condition     = can(regex("^arn:aws:ecs:", var.cluster_arn))
    error_message = "The cluster_arn must be a valid ECS cluster ARN."
  }
}

################################################################################
# Task Definition
################################################################################

variable "task_cpu" {
  type        = number
  description = "The number of CPU units for the task (256, 512, 1024, 2048, 4096, 8192, 16384)."
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "The task_cpu must be one of: 256, 512, 1024, 2048, 4096, 8192, 16384."
  }
}

variable "task_memory" {
  type        = number
  description = "The amount of memory (in MiB) for the task."
  default     = 512

  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 122880
    error_message = "The task_memory must be between 512 and 122880 MiB."
  }
}

variable "launch_type" {
  type        = string
  description = "The launch type for the service (FARGATE or EC2)."
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "The launch_type must be either 'FARGATE' or 'EC2'."
  }
}

variable "network_mode" {
  type        = string
  description = "The Docker networking mode for the containers (awsvpc, bridge, host, none)."
  default     = "awsvpc"

  validation {
    condition     = contains(["awsvpc", "bridge", "host", "none"], var.network_mode)
    error_message = "The network_mode must be one of: awsvpc, bridge, host, none."
  }
}

variable "requires_compatibilities" {
  type        = list(string)
  description = "The launch type compatibility requirements for the task."
  default     = ["FARGATE"]

  validation {
    condition     = alltrue([for c in var.requires_compatibilities : contains(["FARGATE", "EC2", "EXTERNAL"], c)])
    error_message = "Each requires_compatibilities value must be one of: FARGATE, EC2, EXTERNAL."
  }
}

variable "runtime_platform" {
  type = object({
    operating_system_family = optional(string, "LINUX")
    cpu_architecture        = optional(string, "X86_64")
  })
  description = "The runtime platform configuration for the task."
  default     = {}

  validation {
    condition     = contains(["LINUX", "WINDOWS_SERVER_2019_FULL", "WINDOWS_SERVER_2019_CORE", "WINDOWS_SERVER_2022_FULL", "WINDOWS_SERVER_2022_CORE"], var.runtime_platform.operating_system_family)
    error_message = "The operating_system_family must be a valid OS family."
  }

  validation {
    condition     = contains(["X86_64", "ARM64"], var.runtime_platform.cpu_architecture)
    error_message = "The cpu_architecture must be either 'X86_64' or 'ARM64'."
  }
}

################################################################################
# Container Port
################################################################################

variable "container_port" {
  type        = number
  description = "The port the placeholder container listens on. The external deployment controller will update with the actual container configuration."
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "The container_port must be between 1 and 65535."
  }
}

################################################################################
# Volumes
################################################################################

variable "volumes" {
  type = list(object({
    name = string

    efs_volume_configuration = optional(object({
      file_system_id          = string
      root_directory          = optional(string, "/")
      transit_encryption      = optional(string, "ENABLED")
      transit_encryption_port = optional(number, null)
      authorization_config = optional(object({
        access_point_id = optional(string, null)
        iam             = optional(string, "DISABLED")
      }), null)
    }), null)

    docker_volume_configuration = optional(object({
      scope         = optional(string, "task")
      autoprovision = optional(bool, false)
      driver        = optional(string, null)
      driver_opts   = optional(map(string), null)
      labels        = optional(map(string), null)
    }), null)
  }))
  description = "List of volume definitions for the task."
  default     = []
}

################################################################################
# IAM
################################################################################

variable "execution_role_arn" {
  type        = string
  description = "The ARN of an existing IAM role for task execution. If null, a role will be created."
  default     = null

  validation {
    condition     = try(var.execution_role_arn == null || can(regex("^arn:aws:iam::", var.execution_role_arn)), true)
    error_message = "The execution_role_arn must be a valid IAM role ARN."
  }
}

variable "task_role_arn" {
  type        = string
  description = "The ARN of an existing IAM role for the task. If null, a role will be created."
  default     = null

  validation {
    condition     = try(var.task_role_arn == null || can(regex("^arn:aws:iam::", var.task_role_arn)), true)
    error_message = "The task_role_arn must be a valid IAM role ARN."
  }
}

variable "task_role_policies" {
  type        = list(string)
  description = "List of IAM policy ARNs to attach to the task role (only used if task_role_arn is null)."
  default     = []

  validation {
    condition     = alltrue([for p in var.task_role_policies : can(regex("^arn:aws:iam::", p))])
    error_message = "All task_role_policies must be valid IAM policy ARNs."
  }
}

variable "task_role_inline_policies" {
  type        = map(any)
  description = "Inline IAM policies to attach to the task role, keyed by policy name. Values are policy documents as HCL/JSON objects. Only used if task_role_arn is null."
  default     = {}
}

variable "execution_role_policies" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the execution role (only used if execution_role_arn is null)."
  default     = []

  validation {
    condition     = alltrue([for p in var.execution_role_policies : can(regex("^arn:aws:iam::", p))])
    error_message = "All execution_role_policies must be valid IAM policy ARNs."
  }
}

################################################################################
# ECS Service
################################################################################

variable "desired_count" {
  type        = number
  description = "The desired number of tasks to run. Defaults to 0 for infrastructure-first provisioning."
  default     = 0

  validation {
    condition     = var.desired_count >= 0
    error_message = "The desired_count must be 0 or greater."
  }
}

variable "deployment_type" {
  type        = string
  description = "The deployment type: 'rolling' (ECS) or 'blue_green' (CODE_DEPLOY)."
  default     = "rolling"

  validation {
    condition     = contains(["rolling", "blue_green"], var.deployment_type)
    error_message = "The deployment_type must be either 'rolling' or 'blue_green'."
  }
}

variable "deployment_minimum_healthy_percent" {
  type        = number
  description = "The minimum healthy percent during deployment (rolling deployments only)."
  default     = 100

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 200
    error_message = "The deployment_minimum_healthy_percent must be between 0 and 200."
  }
}

variable "deployment_maximum_percent" {
  type        = number
  description = "The maximum percent during deployment (rolling deployments only)."
  default     = 200

  validation {
    condition     = var.deployment_maximum_percent >= 100 && var.deployment_maximum_percent <= 400
    error_message = "The deployment_maximum_percent must be between 100 and 400."
  }
}

variable "enable_execute_command" {
  type        = bool
  description = "Enable ECS Exec for debugging containers."
  default     = false
}

variable "force_new_deployment" {
  type        = bool
  description = "Force a new deployment of the service."
  default     = false
}

variable "wait_for_steady_state" {
  type        = bool
  description = "Wait for the service to reach a steady state before completing. Default false: the initial TF apply runs against the placeholder hello-world task definition (no real app image yet), which never stabilises. The deploy workflow that pushes the actual image is what waits for steady state."
  default     = false
}

variable "health_check_grace_period_seconds" {
  type        = number
  description = "Seconds to ignore failing load balancer health checks on new tasks."
  default     = 0

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "The health_check_grace_period_seconds must be between 0 and 2147483647."
  }
}

variable "enable_ecs_managed_tags" {
  type        = bool
  description = "Enable Amazon ECS managed tags for the tasks."
  default     = true
}

variable "propagate_tags" {
  type        = string
  description = "Whether to propagate tags from the task definition or service to tasks."
  default     = "SERVICE"

  validation {
    condition     = contains(["TASK_DEFINITION", "SERVICE", "NONE"], var.propagate_tags)
    error_message = "The propagate_tags must be one of: TASK_DEFINITION, SERVICE, NONE."
  }
}

variable "platform_version" {
  type        = string
  description = "The platform version for Fargate tasks."
  default     = "LATEST"
}

variable "capacity_provider_strategies" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  description = "Capacity provider strategies for the service. If empty, uses launch_type instead."
  default     = []
}

################################################################################
# Security Group
################################################################################

variable "security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs to attach to the ECS tasks."
  default     = []

  validation {
    condition     = alltrue([for sg in var.security_group_ids : can(regex("^sg-", sg))])
    error_message = "All security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "Security group ID of the load balancer. When provided, the ECS service ingress rule allows traffic only from this SG instead of the VPC CIDR."
  default     = null

  validation {
    condition     = try(var.load_balancer_security_group_id == null || can(regex("^sg-", var.load_balancer_security_group_id)), true)
    error_message = "The load_balancer_security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access the service (in addition to load balancer)."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All allowed_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

################################################################################
# Load Balancer
################################################################################

variable "load_balancer_attachment_json" {
  type        = string
  description = <<-EOT
    Load balancer configuration as a JSON-encoded string. The control plane
    sends this as a string so it can template ALB/listener ARNs from
    upstream module outputs; the module decodes it into the structured
    object used throughout the resources (see local.load_balancer_attachment).
    Set to null (or empty) to disable load-balancer attachment.

    Schema (after jsondecode):
      {
        "enabled": bool,
        "target_group": {
          "port": number,
          "protocol": "HTTP|HTTPS|TCP|UDP|TLS|TCP_UDP|GENEVE",
          "target_type": "ip|instance|...",
          "deregistration_delay": number,
          "slow_start": number,
          "health_check": { ... },
          "stickiness": { ... } | null
        },
        "listener_rules": [ { "listener_arn": ..., "priority": ..., "conditions": [...], "weight": ... }, ... ],
        "nlb_listener": { ... } | null,
        "container_name": string | null,
        "container_port": number | null
      }
  EOT
  default     = null
}

################################################################################
# Auto Scaling
################################################################################

variable "auto_scaling" {
  type = object({
    enabled      = optional(bool, true)
    min_capacity = number
    max_capacity = number

    target_tracking = optional(list(object({
      policy_name       = string
      target_value      = number
      predefined_metric = optional(string, null)
      custom_metric = optional(object({
        metric_name = string
        namespace   = string
        statistic   = string
        dimensions  = optional(map(string), {})
      }), null)
      scale_in_cooldown  = optional(number, 300)
      scale_out_cooldown = optional(number, 300)
      disable_scale_in   = optional(bool, false)
    })), [])

    scheduled = optional(list(object({
      name         = string
      schedule     = string
      min_capacity = optional(number, null)
      max_capacity = optional(number, null)
      timezone     = optional(string, "UTC")
      start_time   = optional(string, null)
      end_time     = optional(string, null)
    })), [])
  })
  description = "Auto scaling configuration for the service."
  default     = null
}

################################################################################
# Service Discovery
################################################################################

variable "service_discovery" {
  type = object({
    namespace_id    = string
    dns_record_type = optional(string, "A")
    dns_ttl         = optional(number, 10)
    routing_policy  = optional(string, "MULTIVALUE")

    health_check_custom_config = optional(object({
      failure_threshold = optional(number, 1)
    }), null)
  })
  description = "AWS Cloud Map service discovery configuration."
  default     = null
}

################################################################################
# Circuit Breaker
################################################################################

variable "deployment_circuit_breaker" {
  type = object({
    enable   = bool
    rollback = bool
  })
  description = "Deployment circuit breaker configuration."
  default = {
    enable   = true
    rollback = true
  }
}

################################################################################
# ECR Repository
################################################################################

variable "enable_ecr" {
  type        = bool
  description = "Create an ECR repository for this service's container image. When true, a repository is provisioned via the containers/ecr submodule."
  default     = false
}

variable "ecr_repository_name" {
  type        = string
  description = "Name of the ECR repository. If null, defaults to var.name."
  default     = null
}

variable "ecr_image_tag_mutability" {
  type        = string
  description = "Tag mutability setting for the ECR repository."
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "The ecr_image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "ecr_scan_on_push" {
  type        = bool
  description = "Scan images for vulnerabilities on push."
  default     = true
}

variable "ecr_force_delete" {
  type        = bool
  description = "Allow the ECR repository to be deleted even when it contains images."
  default     = false
}

variable "ecr_enable_default_lifecycle_policy" {
  type        = bool
  description = "Apply the submodule's built-in lifecycle policy (expire untagged images and cap retained tagged images)."
  default     = false
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# Ravion-managed service domain (optional)
################################################################################
# When `cluster_parent_domain_id` is set, this module declares a
# `ravion_domain` resource that nests under the cluster's parent domain.
# The cluster's wildcard cert covers it via SNI — no per-service ACM cert
# is issued. A host_header listener rule on the cluster HTTPS listener
# routes requests to this service's target group.
#
# The expected setup: opt the parent `ecs_cluster` module into Ravion
# managed domains (`use_ravion_managed_domains = true`) and pipe its
# outputs into each service:
#
#   module "service" {
#     source                     = ".../compute/ecs_service"
#     cluster_parent_domain_id   = module.cluster.ravion_cluster_domain_id
#     cluster_https_listener_arn = module.cluster.public_alb_https_listener_arn
#   }
#
# The cluster module owns the wildcard cert + the listener default-cert
# binding; this module just adds the child domain + host_header rule.

variable "cluster_parent_domain_id" {
  type        = string
  description = "Id of the cluster's `ravion_domain` (the one with `certificate.wildcard = true`). When set, this service allocates a child domain under it. Leave null to skip Ravion domain wiring entirely."
  default     = null
}

variable "cluster_https_listener_arn" {
  type        = string
  description = "ARN of the cluster ALB's HTTPS listener. The host_header rule that routes the service's child FQDN at its target group is installed here. Required when cluster_parent_domain_id is set."
  default     = null

  validation {
    condition     = try(var.cluster_https_listener_arn == null || can(regex("^arn:aws:elasticloadbalancing:", var.cluster_https_listener_arn)), true)
    error_message = "cluster_https_listener_arn must be a valid ELBv2 listener ARN."
  }
}

variable "ravion_listener_rule_priority" {
  type        = number
  description = "Listener rule priority (1-50000) for the service's host_header rule on the cluster's shared HTTPS listener. Default 0 = auto-derive a stable priority from sha256(var.name), giving every service in a cluster a unique slot without anyone hand-picking. Override with an explicit 1-50000 value when a specific slot matters."
  default     = 0
  validation {
    condition     = var.ravion_listener_rule_priority >= 0 && var.ravion_listener_rule_priority <= 50000
    error_message = "priority must be 0 (auto-derive) or between 1 and 50000."
  }
}

variable "domains" {
  type        = list(string)
  description = "Customer-owned FQDNs to expose this service at (e.g. [\"api.example.com\"]). Setting this opts Mode B: a service-specific ACM cert is issued covering ONLY these domains (max 10), attached to the cluster's HTTPS listener as an SNI extra, and the host_header rule matches the customer's FQDNs instead of the auto-allocated one. The Ravion auto-FQDN is NOT created. Customer adds the ACM validation CNAMEs + the traffic CNAMEs at their own DNS provider — surfaced in the Ravion Domains tab. Empty (default) means Mode A: the service rides the cluster wildcard at the auto-allocated FQDN."
  default     = []

  validation {
    condition     = length(var.domains) <= 10
    error_message = "domains is capped at 10 (ACM default SAN limit; raise per-account via AWS support and bump this if needed)."
  }
}

variable "cluster_alb_dns_name" {
  type        = string
  description = "Cluster ALB's DNS name (module.cluster.public_alb_dns_name). Required when `domains` is non-empty (Mode B) — used as the target for the service cert + as the recommended CNAME target in the Domains tab."
  default     = null
}

variable "cluster_alb_zone_id" {
  type        = string
  description = "Cluster ALB's hosted-zone id (module.cluster.public_alb_zone_id) — the AWS-provided zone for the ALB, NOT a Route53 zone you manage. Required when `domains` is non-empty (Mode B)."
  default     = null
}

variable "ravion_aws_account_id" {
  type        = string
  description = "Ravion `AwsAccount` row id (e.g. `aws_abc123`) — the AWS account the service cert is issued in. Required when `domains` is non-empty (Mode B). Pipe from module.cluster.ravion_aws_account_id."
  default     = null

  validation {
    condition     = try(var.ravion_aws_account_id == null || can(regex("^aws_", var.ravion_aws_account_id)), true)
    error_message = "ravion_aws_account_id must be a Ravion AwsAccount row id (starts with 'aws_')."
  }
}

variable "ravion_aws_region" {
  type        = string
  description = "AWS region the service cert lives in. Defaults to the cluster's region. Required (or defaultable) when `domains` is non-empty (Mode B)."
  default     = null
}
