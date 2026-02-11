################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "database/aurora"
  }
  tags = merge(local.default_tags, var.tags)

  # Engine detection
  is_mysql    = var.engine == "aurora-mysql"
  is_postgres = var.engine == "aurora-postgresql"

  # Port defaults based on engine
  default_port = local.is_mysql ? 3306 : 5432
  port         = coalesce(var.port, local.default_port)

  # Parameter group family derivation
  # If not provided, derive from engine and major version
  # Examples: aurora-mysql8.0, aurora-postgresql16
  default_parameter_group_family = (
    var.engine_version != null ? (
      local.is_mysql ? "aurora-mysql${regex("^[0-9]+\\.[0-9]+", var.engine_version)}" :
      local.is_postgres ? "aurora-postgresql${split(".", var.engine_version)[0]}" :
      null
    ) : null
  )

  # CloudWatch logs validation per engine
  # Aurora MySQL: audit, error, general, slowquery
  # Aurora PostgreSQL: postgresql
  valid_log_exports = {
    aurora-mysql      = ["audit", "error", "general", "slowquery"]
    aurora-postgresql = ["postgresql"]
  }

  # Final snapshot identifier (auto-generate if not provided and skip_final_snapshot is false)
  final_snapshot_identifier = (
    var.skip_final_snapshot ? null :
    coalesce(var.final_snapshot_identifier, "${var.name}-final-snapshot")
  )

  # Resource creation flags
  create_security_group    = var.create_security_group
  create_monitoring_role   = var.create_monitoring_role && var.monitoring_interval > 0
  create_cloudwatch_alarms = var.create_cloudwatch_alarms
  create_subnet_group      = var.db_subnet_group_name == null

  # Resolved resource names
  db_subnet_group_name         = local.create_subnet_group ? aws_db_subnet_group.this[0].name : var.db_subnet_group_name
  cluster_parameter_group_name = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.this[0].name : var.cluster_parameter_group_name
  db_parameter_group_name      = var.create_db_parameter_group ? aws_db_parameter_group.this[0].name : var.db_parameter_group_name

  # Instance map generation
  # If var.instances is non-empty, use it directly
  # Otherwise, generate from instance_class + reader_count
  is_serverless          = var.serverless_v2_scaling != null
  default_instance_class = local.is_serverless ? "db.serverless" : var.instance_class
  reader_instance_class  = coalesce(var.reader_instance_class, local.default_instance_class)

  generated_instances = merge(
    {
      writer = {
        instance_class               = local.default_instance_class
        availability_zone            = null
        publicly_accessible          = null
        promotion_tier               = 0
        performance_insights_enabled = null
        monitoring_interval          = null
        tags                         = null
      }
    },
    {
      for i in range(var.reader_count) : "reader-${i + 1}" => {
        instance_class               = local.reader_instance_class
        availability_zone            = null
        publicly_accessible          = null
        promotion_tier               = i + 1
        performance_insights_enabled = null
        monitoring_interval          = null
        tags                         = null
      }
    }
  )

  instances = length(var.instances) > 0 ? var.instances : local.generated_instances
}
