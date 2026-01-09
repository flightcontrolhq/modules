################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "cache/elasticache"
  }
  tags = merge(local.default_tags, var.tags)

  # Engine detection
  is_redis     = var.engine == "redis"
  is_valkey    = var.engine == "valkey"
  is_memcached = var.engine == "memcached"

  # Redis and Valkey share the same resource types
  is_redis_compatible = local.is_redis || local.is_valkey

  # Resource creation flags
  is_serverless            = var.serverless_enabled && local.is_redis_compatible
  create_replication_group = local.is_redis_compatible && !local.is_serverless
  create_cluster           = local.is_memcached
  create_serverless_cache  = local.is_serverless

  # Security group
  create_security_group = var.create_security_group
  security_group_id     = local.create_security_group ? aws_security_group.this[0].id : var.security_group_id

  # Port defaults
  default_port = local.is_memcached ? 11211 : 6379
  port         = coalesce(var.port, local.default_port)

  # Parameter group family detection
  # If not provided, derive from engine and version
  default_parameter_group_family = local.is_redis ? (
    var.engine_version != null ? "redis${split(".", var.engine_version)[0]}" : "redis7"
    ) : local.is_valkey ? (
    var.engine_version != null ? "valkey${split(".", var.engine_version)[0]}" : "valkey8"
    ) : (
    var.engine_version != null ? "memcached${replace(var.engine_version, "/\\.[0-9]+$/", "")}" : "memcached1.6"
  )
  parameter_group_family = coalesce(var.parameter_group_family, local.default_parameter_group_family)

  # Cluster mode
  cluster_mode_enabled = var.cluster_mode_enabled && local.is_redis_compatible && !local.is_serverless

  # Determine the number of replicas
  # For non-cluster mode Redis/Valkey, replicas_per_node_group is used
  # For Memcached, num_cache_nodes is the total number of nodes
  num_cache_clusters = local.is_redis_compatible && !local.is_serverless ? (
    local.cluster_mode_enabled ? null : var.replicas_per_node_group + 1
  ) : null

  # Automatic failover requires at least one replica
  automatic_failover_enabled = var.automatic_failover_enabled && local.is_redis_compatible && !local.is_serverless && (
    local.cluster_mode_enabled || var.replicas_per_node_group >= 1
  )

  # Multi-AZ requires automatic failover
  multi_az_enabled = var.multi_az_enabled && local.automatic_failover_enabled

  # CloudWatch alarm creation
  create_cloudwatch_alarms = var.create_cloudwatch_alarms && !local.is_serverless

  # Resource identifier for CloudWatch (used in dimensions)
  cloudwatch_dimension_value = local.create_replication_group ? aws_elasticache_replication_group.this[0].id : (
    local.create_cluster ? aws_elasticache_cluster.this[0].cluster_id : null
  )
}
