################################################################################
# Global Cluster (optional)
################################################################################

resource "aws_rds_global_cluster" "this" {
  count = var.create_global_cluster ? 1 : 0

  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  storage_encrypted         = var.storage_encrypted
  database_name             = var.database_name
  deletion_protection       = var.deletion_protection
}

################################################################################
# Aurora Cluster
################################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.name

  # Engine
  engine         = var.engine
  engine_version = var.engine_version

  # Storage
  storage_type      = var.storage_type
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # Network
  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = concat(var.security_group_id != null ? [var.security_group_id] : [], var.security_group_ids)
  port                   = local.port
  network_type           = var.network_type
  availability_zones     = length(var.availability_zones) > 0 ? var.availability_zones : null

  # Authentication
  master_username                     = var.master_username
  master_password                     = var.manage_master_user_password ? null : var.master_password
  manage_master_user_password         = var.manage_master_user_password
  master_user_secret_kms_key_id       = var.manage_master_user_password ? var.master_user_secret_kms_key_id : null
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # Database
  database_name = var.database_name

  # Parameter Group
  db_cluster_parameter_group_name = local.cluster_parameter_group_name

  # Backup
  backup_retention_period   = var.backup_retention_period
  preferred_backup_window   = var.preferred_backup_window
  copy_tags_to_snapshot     = var.copy_tags_to_snapshot
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier
  snapshot_identifier       = var.snapshot_identifier
  backtrack_window          = local.is_mysql ? var.backtrack_window : 0

  # Maintenance
  preferred_maintenance_window = var.preferred_maintenance_window
  allow_major_version_upgrade  = var.allow_major_version_upgrade
  apply_immediately            = var.apply_immediately
  deletion_protection          = var.deletion_protection

  # Monitoring
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Aurora features
  enable_http_endpoint           = var.enable_http_endpoint
  enable_local_write_forwarding  = local.is_mysql ? var.enable_local_write_forwarding : null
  enable_global_write_forwarding = local.is_postgres ? var.enable_global_write_forwarding : null

  # Global database
  global_cluster_identifier = var.global_cluster_identifier
  source_region             = var.source_region

  # Serverless v2 scaling
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless_v2_scaling != null ? [var.serverless_v2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  # Point-in-time restore
  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time != null ? [var.restore_to_point_in_time] : []
    content {
      source_cluster_identifier  = restore_to_point_in_time.value.source_cluster_identifier
      restore_type               = restore_to_point_in_time.value.restore_type
      use_latest_restorable_time = restore_to_point_in_time.value.use_latest_restorable_time
      restore_to_time            = restore_to_point_in_time.value.restore_to_time
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    ignore_changes = [
      snapshot_identifier,
      global_cluster_identifier,
    ]

    precondition {
      condition     = var.create_security_group || var.security_group_id != null || length(var.security_group_ids) > 0
      error_message = "At least one security group must be provided: set create_security_group = true, provide security_group_id, or provide security_group_ids."
    }

    precondition {
      condition     = var.manage_master_user_password || var.master_password != null
      error_message = "master_password is required when manage_master_user_password is false."
    }

    precondition {
      condition     = var.create_cluster_parameter_group || var.cluster_parameter_group_name != null
      error_message = "cluster_parameter_group_name is required when create_cluster_parameter_group is false."
    }

    precondition {
      condition     = var.create_db_parameter_group || var.db_parameter_group_name != null
      error_message = "db_parameter_group_name is required when create_db_parameter_group is false."
    }

    precondition {
      condition     = var.monitoring_interval == 0 || local.create_monitoring_role || var.monitoring_role_arn != null
      error_message = "monitoring_role_arn is required when monitoring_interval > 0 and create_monitoring_role is false."
    }

    precondition {
      condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(local.valid_log_exports[var.engine], log)])
      error_message = "Invalid CloudWatch log export type for ${var.engine}. Valid types: ${join(", ", local.valid_log_exports[var.engine])}"
    }

    precondition {
      condition     = !var.enable_local_write_forwarding || local.is_mysql
      error_message = "enable_local_write_forwarding is only supported on Aurora MySQL."
    }

    precondition {
      condition     = !var.enable_global_write_forwarding || local.is_postgres
      error_message = "enable_global_write_forwarding is only supported on Aurora PostgreSQL."
    }

    precondition {
      condition     = var.backtrack_window == 0 || local.is_mysql
      error_message = "backtrack_window is only supported on Aurora MySQL."
    }

    precondition {
      condition     = !var.enable_activity_stream || var.activity_stream_kms_key_id != null
      error_message = "activity_stream_kms_key_id is required when enable_activity_stream is true."
    }
  }

  depends_on = [
    aws_rds_global_cluster.this,
  ]
}
