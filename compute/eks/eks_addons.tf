################################################################################
# Post-compute Add-ons (CoreDNS, optional EBS CSI)
#
# Must run after the system node group exists — Deployment-kind add-ons deadlock
# without schedulable compute.
################################################################################

module "addons" {
  source = "./modules/eks_addons"

  depends_on = [module.system_node_group]

  # Resolved at the root so managed policy ARNs stay known at plan time; the
  # module-level depends_on above defers the submodule's own data sources.
  partition = data.aws_partition.current.partition

  cluster_name = module.cluster.cluster_name

  coredns_addon_version              = var.coredns_addon_version
  coredns_addon_configuration_values = var.coredns_addon_configuration_values

  ebs_csi_driver_enabled             = var.ebs_csi_driver_enabled
  ebs_csi_addon_version              = var.ebs_csi_addon_version
  ebs_csi_addon_configuration_values = var.ebs_csi_addon_configuration_values

  tags = local.tags
}
