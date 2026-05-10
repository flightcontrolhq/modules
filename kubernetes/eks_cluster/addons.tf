################################################################################
# Core EKS Add-ons
#
# vpc-cni, coredns, and kube-proxy are required for any functioning EKS cluster.
# Managing them as add-ons lets EKS handle compatibility with the control plane
# version. Versions default to AWS-resolved most-recent-compatible.
################################################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_addon_version
  configuration_values        = var.vpc_cni_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_addon_version
  configuration_values        = var.coredns_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_addon_version
  configuration_values        = var.kube_proxy_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

################################################################################
# Pod Identity Agent
#
# Required on the data plane for any aws_eks_pod_identity_association to take
# effect. Defaults on because the helpers this module ships (LB Controller,
# EBS CSI) use Pod Identity.
################################################################################

resource "aws_eks_addon" "pod_identity_agent" {
  count = var.enable_pod_identity_agent ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.pod_identity_agent_addon_version
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
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  configuration_values        = var.ebs_csi_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
}
