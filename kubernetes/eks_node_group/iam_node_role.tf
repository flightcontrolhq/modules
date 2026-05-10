################################################################################
# Node IAM Role
#
# Created only when var.node_role_arn is null. Includes the three policies EKS
# requires for any AL2/AL2023 worker, plus AmazonSSMManagedInstanceCore for
# Session Manager (no-cost convenience that doesn't grant any extra cluster
# privilege).
################################################################################

module "node_role" {
  count = local.create_node_role ? 1 : 0

  source = "../../security/iam"

  name        = "${var.cluster_name}-${var.name}-node"
  description = "EKS managed node group instance role for ${var.cluster_name}/${var.name}"

  trusted_services = ["ec2.amazonaws.com"]

  managed_policy_arns = concat(
    [
      "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ],
    var.additional_node_role_managed_policy_arns,
  )

  inline_policy_statements = var.additional_node_role_inline_policy_statements

  tags = local.tags
}
