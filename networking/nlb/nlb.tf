################################################################################
# Network Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "network"
  subnets            = var.enable_elastic_ips ? null : var.subnet_ids

  enable_deletion_protection                                   = var.enable_deletion_protection
  enable_cross_zone_load_balancing                             = var.enable_cross_zone_load_balancing
  dns_record_client_routing_policy                             = var.dns_record_client_routing_policy
  enforce_security_group_inbound_rules_on_private_link_traffic = var.enforce_security_group_inbound_rules_on_private_link_traffic

  security_groups = var.security_group_ids

  dynamic "subnet_mapping" {
    for_each = var.enable_elastic_ips ? var.subnet_ids : []
    content {
      subnet_id     = subnet_mapping.value
      allocation_id = var.elastic_ip_allocation_ids[index(var.subnet_ids, subnet_mapping.value)]
    }
  }

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
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
      condition     = !var.enable_elastic_ips || length(var.elastic_ip_allocation_ids) == length(var.subnet_ids)
      error_message = "When enable_elastic_ips is true, elastic_ip_allocation_ids must have the same number of elements as subnet_ids."
    }

    precondition {
      condition = alltrue([
        for k, v in var.listeners : contains(keys(var.target_groups), v.target_group_key)
      ])
      error_message = "All listener target_group_key values must reference valid keys in target_groups."
    }
  }
}
