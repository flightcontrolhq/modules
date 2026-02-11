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
}
