locals {
  region = coalesce(var.region, data.aws_region.current.region)
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
  query_log_group_arn                 = var.query_log_group_creation_enabled ? one(aws_cloudwatch_log_group.query_logs[*].arn) : var.query_log_group_arn
  query_log_group_resource_arn        = local.query_log_group_arn != null ? "${trimsuffix(local.query_log_group_arn, ":*")}:*" : null
  query_log_resource_policy_name      = coalesce(var.query_log_resource_policy_name, "route53-query-logs-${replace(trimsuffix(local.zone_name, "."), ".", "-")}")
  query_log_group_retention_in_days   = var.query_log_group_retention_days == 0 ? null : var.query_log_group_retention_days
  route53_query_log_service_principal = "route53.${data.aws_partition.current.dns_suffix}"
  route53_query_log_hosted_zone_arn   = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${local.zone_id}"

  # Route 53 stores record data as character strings of at most 255 characters. Values longer
  # than that must be sent as several quoted strings, which the module does automatically for
  # the record types where multiple character strings are concatenated back into one value.
  character_string_max_length = 255
  chunked_record_types        = ["TXT", "SPF"]

  normalized_records = {
    for v in var.records : join("-", compact([v.type, v.name, (
      v.routing_policy != "simple" ||
      v.weighted_routing_policy != null ||
      v.failover_routing_policy != null ||
      v.latency_routing_policy != null ||
      v.geolocation_routing_policy != null ||
      coalesce(v.multivalue_answer_routing_policy, false) == true
      ) ? v.set_identifier : null])) => {
      name = v.name
      type = v.type
      ttl  = v.alias != null || v.target_type == "alias" ? null : coalesce(v.ttl, v.standard_ttl)
      records = (
        v.alias != null ||
        v.target_type == "alias" ||
        (v.records == null && v.record_values == null && v.record_value == null)
        ) ? null : [
        for value in(v.records != null ? v.records : v.record_values != null ? v.record_values : [v.record_value]) : (
          contains(local.chunked_record_types, v.type) &&
          length(value) > local.character_string_max_length &&
          !strcontains(value, "\"")
          ) ? join(" ", [
            for i in range(ceil(length(value) / local.character_string_max_length)) :
            "\"${substr(
              value,
              i * local.character_string_max_length,
              min(local.character_string_max_length, length(value) - i * local.character_string_max_length)
            )}\""
        ]) : value
      ]
      set_identifier = (
        v.routing_policy != "simple" ||
        v.weighted_routing_policy != null ||
        v.failover_routing_policy != null ||
        v.latency_routing_policy != null ||
        v.geolocation_routing_policy != null ||
        coalesce(v.multivalue_answer_routing_policy, false) == true
      ) ? v.set_identifier : null
      health_check_id = v.health_check_id
      allow_overwrite = v.allow_overwrite

      alias = v.alias != null ? v.alias : v.target_type == "alias" ? {
        name                   = v.alias_name
        zone_id                = v.alias_zone_id
        evaluate_target_health = v.alias_evaluate_target_health
      } : null

      weighted_routing_policy = v.weighted_routing_policy != null ? v.weighted_routing_policy : v.routing_policy == "weighted" ? {
        weight = v.weighted_routing_policy_weight
      } : null

      failover_routing_policy = v.failover_routing_policy != null ? v.failover_routing_policy : v.routing_policy == "failover" ? {
        type = v.failover_routing_policy_type
      } : null

      latency_routing_policy = v.latency_routing_policy != null ? v.latency_routing_policy : v.routing_policy == "latency" ? {
        region = v.latency_routing_policy_region
      } : null

      geolocation_routing_policy = v.geolocation_routing_policy != null ? v.geolocation_routing_policy : v.routing_policy == "geolocation" ? {
        continent   = v.geolocation_routing_policy_continent
        country     = v.geolocation_routing_policy_country
        subdivision = v.geolocation_routing_policy_subdivision
      } : null

      multivalue_answer_routing_policy = v.multivalue_answer_routing_policy != null ? v.multivalue_answer_routing_policy : v.routing_policy == "multivalue" ? true : null
    }
  }
}
