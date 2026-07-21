################################################################################
# Deployment-kind EKS Add-ons
#
# coredns and aws-ebs-csi-driver run as Deployments whose pods need schedulable
# compute. Apply this module only after at least one node group or Fargate
# profile exists — otherwise the add-ons stay DEGRADED and the apply times out.
################################################################################

resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.coredns_addon_version
  configuration_values        = var.coredns_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

################################################################################
# EBS CSI Driver
#
# Wired with a Pod Identity association in pod_identity_ebs_csi.tf rather than
# IRSA — the role is bound at runtime via the Pod Identity Agent.
################################################################################

resource "aws_eks_addon" "ebs_csi" {
  count = var.ebs_csi_driver_enabled ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  configuration_values        = var.ebs_csi_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
}
