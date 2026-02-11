################################################################################
# Aurora Cluster Instances
################################################################################

resource "aws_rds_cluster_instance" "this" {
  for_each = local.instances

  identifier         = "${var.name}-${each.key}"
  cluster_identifier = aws_rds_cluster.this.id

  # Engine
  engine         = var.engine
  engine_version = var.engine_version

  # Instance
  instance_class = coalesce(each.value.instance_class, local.default_instance_class)

  # Network
  db_subnet_group_name = local.db_subnet_group_name
  publicly_accessible  = coalesce(each.value.publicly_accessible, var.publicly_accessible)
  availability_zone    = each.value.availability_zone

  # Parameter Group
  db_parameter_group_name = local.db_parameter_group_name

  # Monitoring
  monitoring_interval = coalesce(each.value.monitoring_interval, var.monitoring_interval)
  monitoring_role_arn = coalesce(each.value.monitoring_interval, var.monitoring_interval) > 0 ? local.monitoring_role_arn : null

  # Performance Insights
  performance_insights_enabled          = coalesce(each.value.performance_insights_enabled, var.performance_insights_enabled)
  performance_insights_retention_period = coalesce(each.value.performance_insights_enabled, var.performance_insights_enabled) ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = coalesce(each.value.performance_insights_enabled, var.performance_insights_enabled) ? var.performance_insights_kms_key_id : null

  # Maintenance
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Certificate
  ca_cert_identifier = var.ca_certificate_identifier

  # Failover priority
  promotion_tier = coalesce(each.value.promotion_tier, var.promotion_tier, 0)

  # Snapshots
  copy_tags_to_snapshot = var.copy_tags_to_snapshot

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}"
  }, each.value.tags != null ? each.value.tags : {})

  depends_on = [
    aws_iam_role_policy_attachment.monitoring,
  ]
}
