locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks"
  }

  tags = merge(local.default_tags, var.tags)

  node_subnet_ids = coalesce(var.node_subnet_ids, var.subnet_ids)

  karpenter_chart_enabled = var.karpenter_enabled && var.karpenter_chart_enabled
}
