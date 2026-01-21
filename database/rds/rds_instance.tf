################################################################################
# RDS Primary Instance
################################################################################

resource "aws_db_instance" "this" {
  identifier = var.name

  # Engine
  engine         = var.engine
  engine_version = var.engine_version
  license_model  = var.license_model

  # Instance
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput

  # Encryption
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id]
  port                   = local.port
  publicly_accessible    = var.publicly_accessible
  availability_zone      = var.multi_az ? null : var.availability_zone
  ca_cert_identifier     = var.ca_cert_identifier

  # High Availability
  multi_az = var.multi_az

  # Authentication
  username                            = var.username
  password                            = var.manage_master_user_password ? null : var.password
  manage_master_user_password         = var.manage_master_user_password
  master_user_secret_kms_key_id       = var.manage_master_user_password ? var.master_user_secret_kms_key_id : null
  iam_database_authentication_enabled = local.iam_database_authentication_enabled

  # Database
  db_name              = local.db_name
  character_set_name   = var.character_set_name
  timezone             = var.timezone
  domain               = var.domain
  domain_iam_role_name = var.domain_iam_role_name

  # Parameter and Option Groups
  parameter_group_name = local.create_parameter_group ? aws_db_parameter_group.this[0].name : var.parameter_group_name
  option_group_name    = local.create_option_group ? aws_db_option_group.this[0].name : var.option_group_name

  # Backup
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  copy_tags_to_snapshot     = var.copy_tags_to_snapshot
  delete_automated_backups  = var.delete_automated_backups
  snapshot_identifier       = var.snapshot_identifier
  final_snapshot_identifier = local.final_snapshot_identifier
  skip_final_snapshot       = var.skip_final_snapshot

  # Point-in-time recovery
  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time != null ? [var.restore_to_point_in_time] : []
    content {
      restore_time                             = restore_to_point_in_time.value.restore_time
      source_db_instance_identifier            = restore_to_point_in_time.value.source_db_instance_identifier
      source_db_instance_automated_backups_arn = restore_to_point_in_time.value.source_db_instance_automated_backups_arn
      source_dbi_resource_id                   = restore_to_point_in_time.value.source_dbi_resource_id
      use_latest_restorable_time               = restore_to_point_in_time.value.use_latest_restorable_time
    }
  }

  # Maintenance
  maintenance_window          = var.maintenance_window
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately
  deletion_protection         = var.deletion_protection

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? (local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null

  # Blue/Green Deployment
  dynamic "blue_green_update" {
    for_each = var.blue_green_update != null ? [var.blue_green_update] : []
    content {
      enabled = blue_green_update.value.enabled
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = var.create_security_group || var.security_group_id != null
      error_message = "security_group_id is required when create_security_group is false."
    }

    precondition {
      condition     = var.manage_master_user_password || var.password != null
      error_message = "password is required when manage_master_user_password is false."
    }

    precondition {
      condition     = local.create_parameter_group || var.parameter_group_name != null
      error_message = "parameter_group_name is required when create_parameter_group is false."
    }

    precondition {
      condition     = var.monitoring_interval == 0 || local.create_monitoring_role || var.monitoring_role_arn != null
      error_message = "monitoring_role_arn is required when monitoring_interval > 0 and create_monitoring_role is false."
    }

    precondition {
      condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(local.valid_log_exports[local.engine_log_type], log)])
      error_message = "Invalid CloudWatch log export type for ${var.engine}. Valid types: ${join(", ", local.valid_log_exports[local.engine_log_type])}"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.monitoring
  ]
}

################################################################################
# RDS Read Replicas
################################################################################

resource "aws_db_instance" "read_replica" {
  count = local.read_replica_count

  identifier = "${var.name}-replica-${count.index + 1}"

  # Replica source
  replicate_source_db = aws_db_instance.this.identifier

  # Instance (read replicas inherit engine from source)
  instance_class     = local.read_replica_instance_class
  storage_type       = var.storage_type
  iops               = var.iops
  storage_throughput = var.storage_throughput

  # Encryption (inherited from source, but can specify KMS key)
  kms_key_id = var.kms_key_id

  # Network
  vpc_security_group_ids = [local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id]
  port                   = local.port
  publicly_accessible    = var.publicly_accessible
  availability_zone      = length(var.read_replica_availability_zones) > count.index ? var.read_replica_availability_zones[count.index] : null
  ca_cert_identifier     = var.ca_cert_identifier

  # Multi-AZ not supported for read replicas in same region
  multi_az = false

  # Authentication (inherited from source)
  iam_database_authentication_enabled = local.iam_database_authentication_enabled

  # Parameter and Option Groups
  parameter_group_name = local.create_parameter_group ? aws_db_parameter_group.this[0].name : var.parameter_group_name
  option_group_name    = local.create_option_group ? aws_db_option_group.this[0].name : var.option_group_name

  # Backup (read replicas have their own backup settings)
  backup_retention_period  = 0 # Disable automated backups for replicas by default
  copy_tags_to_snapshot    = var.copy_tags_to_snapshot
  delete_automated_backups = var.delete_automated_backups
  skip_final_snapshot      = true # No final snapshot for replicas

  # Maintenance
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  deletion_protection        = false # Easier to manage replica lifecycle

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? (local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null

  # Blue/Green Deployment
  dynamic "blue_green_update" {
    for_each = var.blue_green_update != null ? [var.blue_green_update] : []
    content {
      enabled = blue_green_update.value.enabled
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-replica-${count.index + 1}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.monitoring
  ]
}
