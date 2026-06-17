locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/route53"
  }
  tags = merge(local.default_tags, var.tags)

  create_public_zone = var.zone_creation_enabled && !var.private_zone_enabled

  zone_name = var.zone_creation_enabled ? var.name : data.aws_route53_zone.existing[0].name

  zone_id = var.zone_creation_enabled ? (
    var.private_zone_enabled ? aws_route53_zone.private[0].zone_id : aws_route53_zone.public[0].zone_id
  ) : var.zone_id

  is_private_zone = var.zone_creation_enabled ? var.private_zone_enabled : data.aws_route53_zone.existing[0].private_zone

  query_log_group_name                = coalesce(var.query_log_group_name, "/aws/route53/${trimsuffix(local.zone_name, ".")}")
  query_log_group_arn                 = var.query_log_group_creation_enabled ? aws_cloudwatch_log_group.query_logs[0].arn : var.query_log_group_arn
  query_log_group_resource_arn        = "${trimsuffix(local.query_log_group_arn, ":*")}:*"
  query_log_resource_policy_name      = coalesce(var.query_log_resource_policy_name, "route53-query-logs-${replace(trimsuffix(local.zone_name, "."), ".", "-")}")
  query_log_group_retention_in_days   = var.query_log_group_retention_days == 0 ? null : var.query_log_group_retention_days
  route53_query_log_service_principal = "route53.${data.aws_partition.current.dns_suffix}"
  route53_query_log_hosted_zone_arn   = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${local.zone_id}"
}
