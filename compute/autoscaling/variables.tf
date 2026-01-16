################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

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
# Auto Scaling Group - Core Configuration
################################################################################

variable "min_size" {
  type        = number
  description = "The minimum number of instances in the Auto Scaling Group."
  default     = 0

  validation {
    condition     = var.min_size >= 0
    error_message = "The min_size must be 0 or greater."
  }
}

variable "max_size" {
  type        = number
  description = "The maximum number of instances in the Auto Scaling Group."
  default     = 10

  validation {
    condition     = var.max_size >= 1
    error_message = "The max_size must be at least 1."
  }
}

variable "desired_capacity" {
  type        = number
  description = "The desired number of instances in the Auto Scaling Group. If null, defaults to min_size."
  default     = null

  validation {
    condition     = var.desired_capacity == null || var.desired_capacity >= 0
    error_message = "The desired_capacity must be null or 0 or greater."
  }
}

variable "vpc_zone_identifier" {
  type        = list(string)
  description = "A list of subnet IDs where the Auto Scaling Group will launch instances."

  validation {
    condition     = length(var.vpc_zone_identifier) > 0
    error_message = "At least one subnet ID must be provided in vpc_zone_identifier."
  }

  validation {
    condition     = alltrue([for s in var.vpc_zone_identifier : can(regex("^subnet-", s))])
    error_message = "All vpc_zone_identifier values must be valid subnet IDs starting with 'subnet-'."
  }
}

################################################################################
# Auto Scaling Group - Timing and Cooldown
################################################################################

variable "default_cooldown" {
  type        = number
  description = "The amount of time, in seconds, after a scaling activity completes before another scaling activity can start."
  default     = 300

  validation {
    condition     = var.default_cooldown >= 0
    error_message = "The default_cooldown must be 0 or greater."
  }
}

variable "default_instance_warmup" {
  type        = number
  description = "The amount of time, in seconds, until a newly launched instance can contribute to CloudWatch metrics. If null, the value of default_cooldown is used."
  default     = null

  validation {
    condition     = var.default_instance_warmup == null || var.default_instance_warmup >= 0
    error_message = "The default_instance_warmup must be null or 0 or greater."
  }
}

variable "wait_for_capacity_timeout" {
  type        = string
  description = "The maximum duration to wait for ASG instances to become healthy. Set to '0' to disable."
  default     = "10m"
}

################################################################################
# Auto Scaling Group - Instance Protection and Lifecycle
################################################################################

variable "protect_from_scale_in" {
  type        = bool
  description = "Whether newly launched instances are protected from scale in by default."
  default     = false
}

variable "max_instance_lifetime" {
  type        = number
  description = "The maximum amount of time, in seconds, that an instance can be in service. Must be 0 or between 86400 (1 day) and 31536000 (365 days). Set to 0 to disable."
  default     = null

  validation {
    condition     = var.max_instance_lifetime == null || var.max_instance_lifetime == 0 || (var.max_instance_lifetime >= 86400 && var.max_instance_lifetime <= 31536000)
    error_message = "The max_instance_lifetime must be null, 0, or between 86400 (1 day) and 31536000 (365 days)."
  }
}

variable "force_delete" {
  type        = bool
  description = "Whether to force delete the Auto Scaling Group without waiting for instances to terminate."
  default     = false
}

variable "ignore_desired_capacity_changes" {
  type        = bool
  description = "Whether to ignore changes to the desired_capacity attribute. Useful when using external scaling mechanisms."
  default     = false
}

################################################################################
# Auto Scaling Group - Health Checks
################################################################################

variable "health_check_type" {
  type        = string
  description = "The type of health check to perform. Valid values are 'EC2' or 'ELB'."
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "The health_check_type must be 'EC2' or 'ELB'."
  }
}

variable "health_check_grace_period" {
  type        = number
  description = "The time, in seconds, to wait after instance launch before checking health."
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "The health_check_grace_period must be 0 or greater."
  }
}

################################################################################
# Auto Scaling Group - Capacity and Scaling Behavior
################################################################################

variable "capacity_rebalance" {
  type        = bool
  description = "Whether to enable capacity rebalancing for Spot instances when they receive a rebalance recommendation."
  default     = false
}

variable "termination_policies" {
  type        = list(string)
  description = "A list of policies to determine which instances to terminate first during scale in. Valid values: 'OldestInstance', 'NewestInstance', 'OldestLaunchConfiguration', 'OldestLaunchTemplate', 'ClosestToNextInstanceHour', 'AllocationStrategy', 'Default'."
  default     = ["Default"]

  validation {
    condition = alltrue([
      for policy in var.termination_policies :
      contains(["OldestInstance", "NewestInstance", "OldestLaunchConfiguration", "OldestLaunchTemplate", "ClosestToNextInstanceHour", "AllocationStrategy", "Default"], policy)
    ])
    error_message = "Each termination_policy must be one of: 'OldestInstance', 'NewestInstance', 'OldestLaunchConfiguration', 'OldestLaunchTemplate', 'ClosestToNextInstanceHour', 'AllocationStrategy', 'Default'."
  }
}

variable "suspended_processes" {
  type        = list(string)
  description = "A list of Auto Scaling processes to suspend. Valid values: 'Launch', 'Terminate', 'HealthCheck', 'ReplaceUnhealthy', 'AZRebalance', 'AlarmNotification', 'ScheduledActions', 'AddToLoadBalancer', 'InstanceRefresh'."
  default     = []

  validation {
    condition = alltrue([
      for process in var.suspended_processes :
      contains(["Launch", "Terminate", "HealthCheck", "ReplaceUnhealthy", "AZRebalance", "AlarmNotification", "ScheduledActions", "AddToLoadBalancer", "InstanceRefresh"], process)
    ])
    error_message = "Each suspended_process must be one of: 'Launch', 'Terminate', 'HealthCheck', 'ReplaceUnhealthy', 'AZRebalance', 'AlarmNotification', 'ScheduledActions', 'AddToLoadBalancer', 'InstanceRefresh'."
  }
}

################################################################################
# Auto Scaling Group - CloudWatch Metrics
################################################################################

variable "enabled_metrics" {
  type        = list(string)
  description = "A list of CloudWatch metrics to enable for the Auto Scaling Group. Valid values: 'GroupMinSize', 'GroupMaxSize', 'GroupDesiredCapacity', 'GroupInServiceInstances', 'GroupPendingInstances', 'GroupStandbyInstances', 'GroupTerminatingInstances', 'GroupTotalInstances', 'GroupInServiceCapacity', 'GroupPendingCapacity', 'GroupStandbyCapacity', 'GroupTerminatingCapacity', 'GroupTotalCapacity', 'WarmPoolDesiredCapacity', 'WarmPoolWarmedCapacity', 'WarmPoolPendingCapacity', 'WarmPoolTerminatingCapacity', 'WarmPoolTotalCapacity', 'GroupAndWarmPoolDesiredCapacity', 'GroupAndWarmPoolTotalCapacity'."
  default     = []

  validation {
    condition = alltrue([
      for metric in var.enabled_metrics :
      contains([
        "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances",
        "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances",
        "GroupInServiceCapacity", "GroupPendingCapacity", "GroupStandbyCapacity", "GroupTerminatingCapacity",
        "GroupTotalCapacity", "WarmPoolDesiredCapacity", "WarmPoolWarmedCapacity", "WarmPoolPendingCapacity",
        "WarmPoolTerminatingCapacity", "WarmPoolTotalCapacity", "GroupAndWarmPoolDesiredCapacity", "GroupAndWarmPoolTotalCapacity"
      ], metric)
    ])
    error_message = "Each enabled_metric must be a valid CloudWatch metric name for Auto Scaling Groups."
  }
}

variable "metrics_granularity" {
  type        = string
  description = "The granularity to associate with the metrics. The only valid value is '1Minute'."
  default     = "1Minute"

  validation {
    condition     = var.metrics_granularity == "1Minute"
    error_message = "The metrics_granularity must be '1Minute'."
  }
}

################################################################################
# Auto Scaling Group - Service-Linked Role
################################################################################

variable "service_linked_role_arn" {
  type        = string
  description = "The ARN of a custom service-linked role for the Auto Scaling Group. If not specified, the default role is used."
  default     = null

  validation {
    condition     = var.service_linked_role_arn == null || can(regex("^arn:aws:iam::", var.service_linked_role_arn))
    error_message = "The service_linked_role_arn must be null or a valid IAM role ARN starting with 'arn:aws:iam::'."
  }
}

################################################################################
# Auto Scaling Group - Load Balancer Integration
################################################################################

variable "target_group_arns" {
  type        = list(string)
  description = "A list of target group ARNs to associate with the Auto Scaling Group."
  default     = []

  validation {
    condition = alltrue([
      for arn in var.target_group_arns :
      can(regex("^arn:aws:elasticloadbalancing:", arn))
    ])
    error_message = "All target_group_arns must be valid Elastic Load Balancing ARNs starting with 'arn:aws:elasticloadbalancing:'."
  }
}

################################################################################
# Auto Scaling Group - ECS Integration
################################################################################

variable "ecs_managed" {
  type        = bool
  description = "Whether to add the 'AmazonECSManaged' tag for ECS capacity provider integration."
  default     = false
}

################################################################################
# Auto Scaling Group - Tag Propagation
################################################################################

variable "propagate_tags_at_launch" {
  type        = bool
  description = "Whether to propagate tags from the Auto Scaling Group to launched instances."
  default     = true
}
