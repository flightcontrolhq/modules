################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 40
    error_message = "The name must be between 1 and 40 characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "engine" {
  type        = string
  description = "The cache engine to use: redis, valkey, or memcached."
  default     = "redis"

  validation {
    condition     = contains(["redis", "valkey", "memcached"], var.engine)
    error_message = "The engine must be 'redis', 'valkey', or 'memcached'."
  }
}

variable "engine_version" {
  type        = string
  description = "The version number of the cache engine. If not specified, the latest available version will be used."
  default     = null
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the ElastiCache cluster will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the ElastiCache subnet group."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

################################################################################
# Security Group
################################################################################

variable "create_security_group" {
  type        = bool
  description = "Whether to create a security group for the ElastiCache cluster."
  default     = true
}

variable "security_group_id" {
  type        = string
  description = "The ID of an existing security group to use. Required if create_security_group is false."
  default     = null

  validation {
    condition     = var.security_group_id == null || can(regex("^sg-", var.security_group_id))
    error_message = "The security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs allowed to access the ElastiCache cluster."
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All allowed_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "A list of CIDR blocks allowed to access the ElastiCache cluster."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All allowed_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

################################################################################
# Cluster Configuration
################################################################################

variable "node_type" {
  type        = string
  description = "The compute and memory capacity of the nodes (e.g., cache.t4g.micro, cache.r7g.large)."
  default     = "cache.t4g.micro"

  validation {
    condition     = can(regex("^cache\\.", var.node_type))
    error_message = "The node_type must be a valid ElastiCache node type starting with 'cache.'."
  }
}

variable "num_cache_nodes" {
  type        = number
  description = "The number of cache nodes. For Redis without cluster mode, this should be 1 (primary only). For Memcached, this is the number of nodes."
  default     = 1

  validation {
    condition     = var.num_cache_nodes >= 1 && var.num_cache_nodes <= 40
    error_message = "The num_cache_nodes must be between 1 and 40."
  }
}

variable "num_node_groups" {
  type        = number
  description = "The number of node groups (shards) for Redis cluster mode. Set to 1 to disable cluster mode."
  default     = 1

  validation {
    condition     = var.num_node_groups >= 1 && var.num_node_groups <= 500
    error_message = "The num_node_groups must be between 1 and 500."
  }
}

variable "replicas_per_node_group" {
  type        = number
  description = "The number of replica nodes in each node group. Valid values are 0 to 5."
  default     = 0

  validation {
    condition     = var.replicas_per_node_group >= 0 && var.replicas_per_node_group <= 5
    error_message = "The replicas_per_node_group must be between 0 and 5."
  }
}

variable "cluster_mode_enabled" {
  type        = bool
  description = "Enable cluster mode (sharding) for Redis/Valkey. When enabled, data is partitioned across multiple shards."
  default     = false
}

variable "port" {
  type        = number
  description = "The port number on which each cache node accepts connections. Default is 6379 for Redis/Valkey and 11211 for Memcached."
  default     = null

  validation {
    condition     = var.port == null || (var.port >= 1 && var.port <= 65535)
    error_message = "The port must be between 1 and 65535."
  }
}

################################################################################
# Redis/Valkey Specific
################################################################################

variable "auth_token" {
  type        = string
  description = "The password used to access a password protected Redis/Valkey server. Can be specified only if transit_encryption_enabled is true."
  default     = null
  sensitive   = true

  validation {
    condition     = var.auth_token == null || (length(var.auth_token) >= 16 && length(var.auth_token) <= 128)
    error_message = "The auth_token must be between 16 and 128 characters."
  }
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Enable encryption in-transit (TLS) for Redis/Valkey."
  default     = true
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Enable encryption at-rest for Redis/Valkey."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key for at-rest encryption. If not specified, the default AWS managed key is used."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be a valid KMS key ARN."
  }
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover for Redis/Valkey. Requires at least one replica."
  default     = false
}

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ support for Redis/Valkey replication group."
  default     = false
}

################################################################################
# Snapshots
################################################################################

variable "snapshot_retention_limit" {
  type        = number
  description = "The number of days for which ElastiCache retains automatic snapshots. 0 disables backups."
  default     = 0

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "The snapshot_retention_limit must be between 0 and 35."
  }
}

variable "snapshot_window" {
  type        = string
  description = "The daily time range during which automated backups are created (e.g., 05:00-09:00 UTC)."
  default     = null

  validation {
    condition     = var.snapshot_window == null || can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]-([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.snapshot_window))
    error_message = "The snapshot_window must be in the format HH:MM-HH:MM (e.g., 05:00-09:00)."
  }
}

variable "final_snapshot_identifier" {
  type        = string
  description = "The name of the final snapshot to create when deleting the replication group. If not specified, no final snapshot is created."
  default     = null
}

################################################################################
# Maintenance
################################################################################

variable "maintenance_window" {
  type        = string
  description = "The weekly time range for maintenance (e.g., sun:05:00-sun:09:00 UTC)."
  default     = null

  validation {
    condition     = var.maintenance_window == null || can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "The maintenance_window must be in the format ddd:HH:MM-ddd:HH:MM (e.g., sun:05:00-sun:09:00)."
  }
}

variable "apply_immediately" {
  type        = bool
  description = "Whether to apply changes immediately or during the next maintenance window."
  default     = false
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades during the maintenance window."
  default     = true
}

################################################################################
# Parameter Group
################################################################################

variable "parameter_group_family" {
  type        = string
  description = "The family of the ElastiCache parameter group (e.g., redis7, valkey8, memcached1.6). If not specified, it is derived from the engine and version."
  default     = null
}

variable "parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "A list of parameter name/value pairs to apply to the parameter group."
  default     = []
}

################################################################################
# Notifications
################################################################################

variable "notification_topic_arn" {
  type        = string
  description = "The ARN of an SNS topic to send ElastiCache notifications to."
  default     = null

  validation {
    condition     = var.notification_topic_arn == null || can(regex("^arn:aws:sns:", var.notification_topic_arn))
    error_message = "The notification_topic_arn must be a valid SNS topic ARN."
  }
}

################################################################################
# CloudWatch Alarms
################################################################################

variable "create_cloudwatch_alarms" {
  type        = bool
  description = "Create CloudWatch alarms for CPU, memory, and connections."
  default     = false
}

variable "cloudwatch_alarm_cpu_threshold" {
  type        = number
  description = "The CPU utilization threshold (percent) for the CloudWatch alarm."
  default     = 80

  validation {
    condition     = var.cloudwatch_alarm_cpu_threshold >= 0 && var.cloudwatch_alarm_cpu_threshold <= 100
    error_message = "The cloudwatch_alarm_cpu_threshold must be between 0 and 100."
  }
}

variable "cloudwatch_alarm_memory_threshold" {
  type        = number
  description = "The memory utilization threshold (percent) for the CloudWatch alarm."
  default     = 80

  validation {
    condition     = var.cloudwatch_alarm_memory_threshold >= 0 && var.cloudwatch_alarm_memory_threshold <= 100
    error_message = "The cloudwatch_alarm_memory_threshold must be between 0 and 100."
  }
}

variable "cloudwatch_alarm_connections_threshold" {
  type        = number
  description = "The current connections threshold for the CloudWatch alarm."
  default     = 1000

  validation {
    condition     = var.cloudwatch_alarm_connections_threshold >= 1
    error_message = "The cloudwatch_alarm_connections_threshold must be at least 1."
  }
}

variable "cloudwatch_alarm_actions" {
  type        = list(string)
  description = "A list of ARNs to notify when the CloudWatch alarm transitions to ALARM state."
  default     = []
}

variable "cloudwatch_ok_actions" {
  type        = list(string)
  description = "A list of ARNs to notify when the CloudWatch alarm transitions to OK state."
  default     = []
}

################################################################################
# Serverless
################################################################################

variable "serverless_enabled" {
  type        = bool
  description = "Create an ElastiCache Serverless cache instead of a provisioned cluster."
  default     = false
}

variable "serverless_cache_usage_limits" {
  type = object({
    data_storage_maximum    = optional(number, 10)
    ecpu_per_second_maximum = optional(number, 5000)
  })
  description = "Usage limits for ElastiCache Serverless. data_storage_maximum is in GB, ecpu_per_second_maximum is the max ECPUs per second."
  default     = {}

  validation {
    condition     = var.serverless_cache_usage_limits.data_storage_maximum == null || (var.serverless_cache_usage_limits.data_storage_maximum >= 1 && var.serverless_cache_usage_limits.data_storage_maximum <= 5000)
    error_message = "The data_storage_maximum must be between 1 and 5000 GB."
  }

  validation {
    condition     = var.serverless_cache_usage_limits.ecpu_per_second_maximum == null || (var.serverless_cache_usage_limits.ecpu_per_second_maximum >= 1000 && var.serverless_cache_usage_limits.ecpu_per_second_maximum <= 15000000)
    error_message = "The ecpu_per_second_maximum must be between 1000 and 15000000."
  }
}

variable "serverless_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs to associate with the serverless cache. If not specified, the module will use the security group created/provided by this module."
  default     = null

  validation {
    condition     = var.serverless_security_group_ids == null || alltrue([for sg in var.serverless_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All serverless_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "serverless_snapshot_arns_to_restore" {
  type        = list(string)
  description = "A list of snapshot ARNs to restore the serverless cache from."
  default     = null
}

variable "serverless_daily_snapshot_time" {
  type        = string
  description = "The daily time for automated snapshots in UTC (HH:MM format) for serverless cache."
  default     = null

  validation {
    condition     = var.serverless_daily_snapshot_time == null || can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.serverless_daily_snapshot_time))
    error_message = "The serverless_daily_snapshot_time must be in HH:MM format (e.g., 05:00)."
  }
}
