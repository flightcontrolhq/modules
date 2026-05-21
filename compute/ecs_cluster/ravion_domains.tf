################################################################################
# Cluster-side instantiation of the shared cert-groups module in parent mode.
#
# Each row in var.ravion_certificate_groups creates ONE wildcard ACM
# cert + ONE parent DomainAllocation services can nest under. NO
# listener rules + NO routing records at the cluster level — services
# own routing for their leaf FQDNs.
################################################################################

module "ravion_cert_groups" {
  source = "../../_shared/ravion_cert_groups"

  name               = var.name
  mode               = "parent"
  cert_groups        = var.ravion_certificate_groups
  module_instance_id = var.module_instance_id

  # SNI cert attachment lands on the cluster's HTTPS listener.
  listener_arn = var.enable_public_alb && var.public_alb_enable_https ? module.public_alb[0].https_listener_arn : null

  tags = var.tags
}
