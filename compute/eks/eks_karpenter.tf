################################################################################
# Karpenter (optional)
################################################################################

module "karpenter" {
  source = "./modules/eks_karpenter"
  count  = var.karpenter_enabled ? 1 : 0

  depends_on = [module.addons]

  cluster_name = module.cluster.cluster_name

  controller_namespace       = var.karpenter_controller_namespace
  controller_service_account = var.karpenter_controller_service_account

  node_role_additional_managed_policy_arns = var.karpenter_node_role_additional_managed_policy_arns

  interruption_queue_name                      = var.karpenter_interruption_queue_name
  interruption_queue_message_retention_seconds = var.karpenter_interruption_queue_message_retention_seconds

  tags = local.tags
}
