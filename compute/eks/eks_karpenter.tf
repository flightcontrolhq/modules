################################################################################
# Karpenter (optional)
################################################################################

module "karpenter" {
  source = "./modules/eks_karpenter"
  count  = var.karpenter_enabled ? 1 : 0

  depends_on = [module.addons]

  # Resolved at the root so managed policy ARNs stay known at plan time; the
  # module-level depends_on above defers the submodule's own data sources.
  partition = data.aws_partition.current.partition

  cluster_name = module.cluster.cluster_name

  controller_namespace       = var.karpenter_controller_namespace
  controller_service_account = var.karpenter_controller_service_account

  node_role_additional_managed_policy_arns = var.karpenter_node_role_additional_managed_policy_arns

  interruption_queue_name                      = var.karpenter_interruption_queue_name
  interruption_queue_message_retention_seconds = var.karpenter_interruption_queue_message_retention_seconds

  tags = local.tags
}

################################################################################
# Karpenter controller and default NodePool (Helm) are intentionally NOT
# installed by this stack — see compute/eks/components. Keeping this stack
# pure AWS API means it provisions in a single apply with no connectivity to
# the cluster's Kubernetes endpoint.
################################################################################
