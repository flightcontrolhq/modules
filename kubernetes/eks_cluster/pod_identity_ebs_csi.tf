################################################################################
# EBS CSI Driver — Pod Identity Role
#
# AmazonEBSCSIDriverPolicy is the AWS-managed policy maintained for this
# component; we attach it directly rather than vendoring the JSON.
################################################################################

module "ebs_csi_role" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  source = "../../security/iam"

  name        = "${var.name}-ebs-csi"
  description = "EBS CSI driver Pod Identity role for ${var.name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  managed_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
  ]

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = module.ebs_csi_role[0].role_arn

  tags = local.tags
}
