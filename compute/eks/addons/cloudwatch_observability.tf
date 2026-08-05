################################################################################
# CloudWatch Observability / Container Insights (optional add-on)
#
# Installs the CloudWatch agent and Fluent Bit as DaemonSets. The add-on runs
# two DaemonSets with separate service accounts (cloudwatch-agent for metrics,
# fluent-bit for container logs); both need the same CloudWatch permissions,
# so they share one role via two associations. Without the fluent-bit
# association, log shipping silently falls back to the node role, which does
# not carry CloudWatch permissions.
################################################################################

module "cloudwatch_observability_role" {
  count = var.cloudwatch_observability_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-cloudwatch-observability"
  description = "CloudWatch Observability add-on Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
  ]

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  count = var.cloudwatch_observability_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = module.cloudwatch_observability_role[0].role_arn

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  count = var.cloudwatch_observability_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "fluent-bit"
  role_arn        = module.cloudwatch_observability_role[0].role_arn

  tags = local.tags
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.cloudwatch_observability_enabled ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = var.cloudwatch_observability_addon_version
  configuration_values        = var.cloudwatch_observability_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_eks_pod_identity_association.fluent_bit,
  ]
}
