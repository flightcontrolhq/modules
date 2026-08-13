################################################################################
# CloudWatch Observability / Container Insights (optional add-on)
#
# Installs the CloudWatch agent and Fluent Bit as DaemonSets. The add-on runs
# two DaemonSets with separate service accounts (cloudwatch-agent for metrics,
# fluent-bit for container logs); both need the same CloudWatch permissions,
# so they share one role via two associations. Without the fluent-bit
# association, log shipping silently falls back to the node role, which does
# not carry CloudWatch permissions.
#
# When metrics_enabled is on, the add-on is trimmed to logs only. Container
# Insights and the AMP pipeline measure the same containers, so leaving both on
# is two bills for one answer — and the coarser of the two is the one being
# paid for per metric. Logs stay, because the cluster module's Logs tab and the
# service log views are addressed to the log groups this add-on writes.
################################################################################

locals {
  # Verified against the add-on's published configuration schema
  # (`aws eks describe-addon-configuration`): these three keys exist from
  # add-on v6.0.0 onward, and disabling both metric features while keeping
  # containerLogs is a combination AWS itself tests. With containerInsights and
  # applicationSignals off, the CloudWatch agent's rendered config collapses to
  # `{"agent":{"region":"..."}}` and it emits no metrics.
  #
  # The agent DaemonSet itself is deliberately left running: Fluent Bit's
  # kubernetes filter uses `Use_Pod_Association On`, which resolves pod entity
  # metadata through the agent, so disabling it would degrade the logs that are
  # the whole point of keeping the add-on.
  cloudwatch_observability_logs_only_configuration_values = jsonencode({
    containerInsights  = { enabled = false }
    applicationSignals = { enabled = false }
    containerLogs      = { enabled = true }
  })

  # An explicit override always wins: this default only fills a null.
  cloudwatch_observability_logs_only_applied = (
    var.cloudwatch_observability_enabled &&
    var.metrics_enabled &&
    var.cloudwatch_observability_addon_configuration_values == null
  )

  cloudwatch_observability_configuration_values = (
    var.cloudwatch_observability_addon_configuration_values != null
    ? var.cloudwatch_observability_addon_configuration_values
    : (var.metrics_enabled ? local.cloudwatch_observability_logs_only_configuration_values : null)
  )

  # Fluent Bit's application output uses `log_stream_prefix ${HOST_NAME}-` with
  # the tail input's tag appended, and HOST_NAME is the node name. The stream is
  # therefore node-first: a per-service reader filters on the substring or on
  # the kubernetes.* fields inside each event, not on a stream prefix.
  container_log_stream_template = "{node_name}-application.var.log.containers.{pod_name}_{namespace}_{container_name}-{container_id}.log"
}

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
  configuration_values        = local.cloudwatch_observability_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_eks_pod_identity_association.fluent_bit,
  ]

  lifecycle {
    # EKS validates configuration_values against the add-on version's schema and
    # rejects unknown keys, so the logs-only default cannot be sent to a version
    # that predates them. Caught here rather than as an opaque API error on a
    # ten-minute add-on update.
    precondition {
      condition = (
        !local.cloudwatch_observability_logs_only_applied ||
        var.cloudwatch_observability_addon_version == null ||
        try(tonumber(regex("^v([0-9]+)\\.", var.cloudwatch_observability_addon_version)[0]) >= 6, false)
      )
      error_message = "metrics_enabled trims the amazon-cloudwatch-observability add-on to logs only, which needs add-on v6.0.0 or later (the containerInsights / applicationSignals configuration keys do not exist before it). Either leave cloudwatch_observability_addon_version null so AWS resolves a current version, pin v6.0.0 or later, or set cloudwatch_observability_addon_configuration_values explicitly to keep full control."
    }
  }
}
