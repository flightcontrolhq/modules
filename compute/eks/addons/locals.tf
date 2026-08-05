################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/addons"
  }

  tags = merge(local.default_tags, var.tags)

  # Shared trust policy for EKS Pod Identity roles: the role is bound to a
  # service account at runtime via the Pod Identity Agent.
  pod_identity_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
