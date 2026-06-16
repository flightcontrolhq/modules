################################################################################
# Network Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal_load_balancer_enabled
  load_balancer_type = "network"
  subnets            = var.elastic_ips_enabled ? null : var.subnet_ids

  enable_deletion_protection                                   = var.deletion_protection_enabled
  enable_cross_zone_load_balancing                             = var.cross_zone_load_balancing_enabled
  dns_record_client_routing_policy                             = var.dns_record_client_routing_policy
  enforce_security_group_inbound_rules_on_private_link_traffic = var.enforce_security_group_inbound_rules_on_private_link_traffic

  security_groups = concat([module.security_group.security_group_id], var.additional_security_group_ids)

  dynamic "subnet_mapping" {
    for_each = var.elastic_ips_enabled ? var.subnet_ids : []
    content {
      subnet_id     = subnet_mapping.value
      allocation_id = var.elastic_ip_allocation_ids[index(var.subnet_ids, subnet_mapping.value)]
    }
  }

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [1] : []
    content {
      bucket  = local.access_logs_bucket_name
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  depends_on = [
    aws_s3_bucket_policy.access_logs
  ]

  lifecycle {
    precondition {
      condition     = !var.elastic_ips_enabled || length(var.elastic_ip_allocation_ids) == length(var.subnet_ids)
      error_message = "When elastic_ips_enabled is true, elastic_ip_allocation_ids must have the same number of elements as subnet_ids."
    }
  }
}
