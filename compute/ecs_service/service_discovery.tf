################################################################################
# AWS Cloud Map Service Discovery
################################################################################

resource "aws_service_discovery_service" "this" {
  count = local.enable_service_discovery ? 1 : 0

  name = var.name

  dns_config {
    namespace_id   = var.service_discovery.namespace_id
    routing_policy = var.service_discovery.routing_policy

    dns_records {
      ttl  = var.service_discovery.dns_ttl
      type = var.service_discovery.dns_record_type
    }
  }

  dynamic "health_check_custom_config" {
    for_each = var.service_discovery.health_check_custom_config != null ? [var.service_discovery.health_check_custom_config] : []
    content {
      failure_threshold = health_check_custom_config.value.failure_threshold
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })
}


