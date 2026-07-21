################################################################################
# Fargate Profiles (optional)
################################################################################

module "fargate_profiles" {
  source   = "./modules/eks_fargate_profile"
  for_each = var.fargate_profiles

  depends_on = [module.addons]

  cluster_name = module.cluster.cluster_name
  name         = each.key
  subnet_ids   = coalesce(each.value.subnet_ids, local.node_subnet_ids)
  selectors    = each.value.selectors

  pod_execution_role_arn = each.value.pod_execution_role_arn

  tags = local.tags
}
