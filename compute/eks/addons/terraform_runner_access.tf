################################################################################
# Terraform Runner Access Entry
#
# The Helm releases authenticate to the Kubernetes API as the IAM role running
# Terraform (via `aws eks get-token`). With the cluster in API authentication
# mode, that role needs an EKS access entry — cluster-creator admin only covers
# the identity that originally created the cluster, not this stack's runner.
# The role is resolved at apply time so ephemeral per-run pipeline roles work;
# when the role changes between runs, the entry is simply replaced.
################################################################################

data "aws_caller_identity" "current" {}

# Resolves the assumed-role session ARN back to the underlying IAM role ARN,
# which is what EKS access entries expect as the principal.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_eks_access_entry" "terraform_runner" {
  count = var.karpenter_enabled && var.terraform_runner_access_entry_enabled ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  type          = "STANDARD"

  tags = local.tags
}

resource "aws_eks_access_policy_association" "terraform_runner_admin" {
  count = var.karpenter_enabled && var.terraform_runner_access_entry_enabled ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = aws_eks_access_entry.terraform_runner[0].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
