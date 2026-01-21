################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "database/rds"
  }
  tags = merge(local.default_tags, var.tags)

  # Engine detection
  is_mysql     = var.engine == "mysql"
  is_postgres  = var.engine == "postgres"
  is_mariadb   = var.engine == "mariadb"
  is_oracle    = startswith(var.engine, "oracle-")
  is_sqlserver = startswith(var.engine, "sqlserver-")

  # Port defaults based on engine
  default_port = (
    local.is_mysql || local.is_mariadb ? 3306 :
    local.is_postgres ? 5432 :
    local.is_oracle ? 1521 :
    local.is_sqlserver ? 1433 :
    3306
  )
  port = coalesce(var.port, local.default_port)

  # Parameter group family derivation
  # If not provided, derive from engine and major version
  # Examples: mysql8.0, postgres15, mariadb10.6, oracle-ee-19, sqlserver-ee-15.0
  default_parameter_group_family = (
    var.engine_version != null ? (
      local.is_mysql ? "mysql${regex("^[0-9]+\\.[0-9]+", var.engine_version)}" :
      local.is_postgres ? "postgres${split(".", var.engine_version)[0]}" :
      local.is_mariadb ? "mariadb${regex("^[0-9]+\\.[0-9]+", var.engine_version)}" :
      local.is_oracle ? "${var.engine}-${split(".", var.engine_version)[0]}" :
      local.is_sqlserver ? "${var.engine}-${regex("^[0-9]+\\.[0-9]+", var.engine_version)}" :
      null
    ) : null
  )
  parameter_group_family = coalesce(var.parameter_group_family, local.default_parameter_group_family)

  # Option group major engine version derivation
  # For Oracle: 19, 21
  # For SQL Server: 15.00, 16.00
  default_option_group_engine_version = (
    var.engine_version != null ? (
      local.is_oracle ? split(".", var.engine_version)[0] :
      local.is_sqlserver ? regex("^[0-9]+\\.[0-9]+", var.engine_version) :
      split(".", var.engine_version)[0]
    ) : null
  )
  option_group_engine_version = coalesce(var.option_group_engine_version, local.default_option_group_engine_version)

  # Resource creation flags
  create_security_group  = var.create_security_group
  create_parameter_group = var.create_parameter_group
  create_option_group    = var.create_option_group && (local.is_oracle || local.is_sqlserver)
  create_monitoring_role = var.create_monitoring_role && var.monitoring_interval > 0

  # Read replica creation
  create_read_replicas = var.create_read_replica && var.read_replica_count > 0
  read_replica_count   = local.create_read_replicas ? var.read_replica_count : 0

  # Read replica instance class (defaults to primary if not specified)
  read_replica_instance_class = coalesce(var.read_replica_instance_class, var.instance_class)

  # CloudWatch alarm creation
  create_cloudwatch_alarms = var.create_cloudwatch_alarms

  # CloudWatch logs validation per engine
  # MySQL: audit, error, general, slowquery
  # PostgreSQL: postgresql, upgrade
  # MariaDB: audit, error, general, slowquery
  # Oracle: alert, audit, listener, trace, oemagent
  # SQL Server: agent, error
  valid_log_exports = {
    mysql     = ["audit", "error", "general", "slowquery"]
    postgres  = ["postgresql", "upgrade"]
    mariadb   = ["audit", "error", "general", "slowquery"]
    oracle    = ["alert", "audit", "listener", "trace", "oemagent"]
    sqlserver = ["agent", "error"]
  }
  engine_log_type = (
    local.is_mysql ? "mysql" :
    local.is_postgres ? "postgres" :
    local.is_mariadb ? "mariadb" :
    local.is_oracle ? "oracle" :
    local.is_sqlserver ? "sqlserver" :
    "mysql"
  )

  # Final snapshot identifier (auto-generate if not provided and skip_final_snapshot is false)
  final_snapshot_identifier = (
    var.skip_final_snapshot ? null :
    coalesce(var.final_snapshot_identifier, "${var.name}-final-snapshot")
  )

  # IAM database authentication is only supported for MySQL and PostgreSQL
  iam_database_authentication_enabled = var.iam_database_authentication_enabled && (local.is_mysql || local.is_postgres)

  # DB name handling - SQL Server doesn't support db_name at creation time
  db_name = local.is_sqlserver ? null : var.db_name
}
