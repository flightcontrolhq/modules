################################################################################
# ElastiCache Replication Group (Redis/Valkey)
################################################################################

resource "aws_elasticache_replication_group" "this" {
  count = local.create_replication_group ? 1 : 0

  replication_group_id = var.name
  description          = "ElastiCache replication group for ${var.name}"

  # Engine
  engine               = var.engine
  engine_version       = var.engine_version
  parameter_group_name = aws_elasticache_parameter_group.this[0].name

  # Node configuration
  node_type = var.node_type
  port      = local.port

  # Cluster mode configuration
  num_node_groups         = local.cluster_mode_enabled ? var.num_node_groups : null
  replicas_per_node_group = local.cluster_mode_enabled ? var.replicas_per_node_group : null
  num_cache_clusters      = local.cluster_mode_enabled ? null : local.num_cache_clusters

  # High availability
  automatic_failover_enabled  = local.automatic_failover_enabled
  multi_az_enabled            = local.multi_az_enabled
  global_replication_group_id = var.global_replication_group_id
  data_tiering_enabled        = var.data_tiering_enabled

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.this[0].name
  security_group_ids = [local.security_group_id]
  network_type       = var.network_type
  ip_discovery       = var.ip_discovery

  # Security
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.auth_token
  kms_key_id                 = var.kms_key_arn

  # Log delivery
  dynamic "log_delivery_configuration" {
    for_each = var.log_delivery_configuration
    content {
      destination      = log_delivery_configuration.value.destination
      destination_type = log_delivery_configuration.value.destination_type
      log_format       = log_delivery_configuration.value.log_format
      log_type         = log_delivery_configuration.value.log_type
    }
  }

  # Snapshots
  snapshot_retention_limit  = var.snapshot_retention_limit
  snapshot_window           = var.snapshot_window
  final_snapshot_identifier = var.final_snapshot_identifier

  # Maintenance
  maintenance_window         = var.maintenance_window
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Notifications
  notification_topic_arn = var.notification_topic_arn

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = var.auth_token == null || var.transit_encryption_enabled
      error_message = "auth_token requires transit_encryption_enabled to be true."
    }

    precondition {
      condition     = !local.automatic_failover_enabled || (local.cluster_mode_enabled || var.replicas_per_node_group >= 1)
      error_message = "Automatic failover requires at least one replica (replicas_per_node_group >= 1) or cluster mode enabled."
    }

    precondition {
      condition     = var.create_security_group || var.security_group_id != null
      error_message = "security_group_id is required when create_security_group is false."
    }

    ignore_changes = [
      num_cache_clusters,
    ]
  }
}

################################################################################
# ElastiCache Cluster (Memcached)
################################################################################

resource "aws_elasticache_cluster" "this" {
  count = local.create_cluster ? 1 : 0

  cluster_id = var.name

  # Engine
  engine               = var.engine
  engine_version       = var.engine_version
  parameter_group_name = aws_elasticache_parameter_group.this[0].name

  # Node configuration
  node_type       = var.node_type
  num_cache_nodes = var.num_cache_nodes
  port            = local.port

  # For Memcached, AZ placement strategy
  az_mode = var.num_cache_nodes > 1 ? "cross-az" : "single-az"

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.this[0].name
  security_group_ids = [local.security_group_id]

  # Maintenance
  maintenance_window         = var.maintenance_window
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Notifications
  notification_topic_arn = var.notification_topic_arn

  tags = merge(local.tags, {
    Name = var.name
  })
}

################################################################################
# ElastiCache Serverless Cache (Redis/Valkey)
################################################################################

resource "aws_elasticache_serverless_cache" "this" {
  count = local.create_serverless_cache ? 1 : 0

  name        = var.name
  description = "ElastiCache Serverless cache for ${var.name}"
  engine      = var.engine

  # Usage limits
  cache_usage_limits {
    data_storage {
      maximum = var.serverless_cache_usage_limits.data_storage_maximum
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = var.serverless_cache_usage_limits.ecpu_per_second_maximum
    }
  }

  # Network
  subnet_ids         = var.subnet_ids
  security_group_ids = coalesce(var.serverless_security_group_ids, [local.security_group_id])

  # Security
  kms_key_id = var.kms_key_arn

  # Snapshots
  snapshot_retention_limit = var.snapshot_retention_limit > 0 ? var.snapshot_retention_limit : null
  daily_snapshot_time      = var.serverless_daily_snapshot_time
  snapshot_arns_to_restore = var.serverless_snapshot_arns_to_restore

  tags = merge(local.tags, {
    Name = var.name
  })
}
