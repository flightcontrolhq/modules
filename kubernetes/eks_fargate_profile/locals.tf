locals {
  region    = coalesce(var.region, data.aws_region.current.id)
  partition = data.aws_partition.current.partition
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "kubernetes/eks_fargate_profile"
  }

  tags = merge(local.default_tags, var.tags)

  create_role = var.pod_execution_role_arn == null
  role_arn    = local.create_role ? module.pod_execution_role[0].role_arn : var.pod_execution_role_arn
}
