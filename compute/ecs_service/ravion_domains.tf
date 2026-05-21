################################################################################
# Service-side instantiation of the shared cert-groups module.
#
# All allocation / cert / DNS-record / listener-rule resources live in
# `modules/_shared/ravion_cert_groups`. This file just wires up the
# routing target (cluster's ALB DNS + zone + HTTPS listener + this
# service's target group) and forwards the operator's
# `var.ravion_certificate_groups`.
################################################################################

module "ravion_cert_groups" {
  source = "../../_shared/ravion_cert_groups"

  name                               = var.name
  cert_groups                        = var.ravion_certificate_groups
  module_instance_given_id           = var.module_instance_given_id
  ravion_parent_domain_allocation_id = var.ravion_parent_domain_allocation_id
  ravion_dns_provider_id             = var.ravion_dns_provider_id
  routing_target_dns_name            = var.ravion_cluster_alb_dns_name
  routing_target_zone_id             = var.ravion_cluster_alb_zone_id
  listener_arn                       = var.ravion_cluster_https_listener_arn
  target_group_arn                   = try(aws_lb_target_group.this[0].arn, null)
  tags                               = var.tags
}
