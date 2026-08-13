################################################################################
# OpenTelemetry collector → Amazon Managed Prometheus (Helm)
#
# A single-replica Deployment running the AWS Distro for OpenTelemetry image
# under the community opentelemetry-collector chart. It scrapes three targets —
# cAdvisor and the kubelet's resource endpoint on every node, through the API
# server proxy, and kube-state-metrics in-cluster — keeps the curated allow-list
# in locals.tf, and remote-writes the survivors to AMP signed with SigV4.
#
# Three things about the shape of this file:
#
#   1. IT IS A HELM RELEASE, NOT THE ADOT EKS ADD-ON. The add-on installs an
#      operator and CRDs, wants cert-manager, and then needs an
#      OpenTelemetryCollector custom resource applied with plan-time cluster
#      connectivity to configure the pipeline at all. A values-driven release is
#      how Karpenter and the External Secrets Operator are installed here.
#
#   2. THE ALLOW-LIST IS THE DESIGN, NOT A TUNING KNOB. AMP bills per sample.
#      Everything outside locals.metrics_*_allowlist is dropped in
#      metric_relabel_configs, which runs before samples enter collector memory,
#      so widening it is the difference between a bill of tens and hundreds of
#      dollars a month. var.metrics_additional_allowlist is the supported way.
#
#   3. ONE REPLICA SCRAPES EVERY NODE. Fine to roughly 100 nodes at a 60s
#      interval. Past that the answer is the chart's target allocator with a
#      StatefulSet, which is deliberately not in this release.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  otel_collector_name = "ravion-otel-collector"

  # Null limits are omitted rather than rendered as null, which Helm would read
  # as "delete this key" — harmless here, but the pod spec is clearer without.
  otel_collector_resource_limits = merge(
    var.otel_collector_resources.cpu_limit == null ? {} : { cpu = var.otel_collector_resources.cpu_limit },
    var.otel_collector_resources.memory_limit == null ? {} : { memory = var.otel_collector_resources.memory_limit },
  )

  otel_collector_resource_requests = merge(
    var.otel_collector_resources.cpu_request == null ? {} : { cpu = var.otel_collector_resources.cpu_request },
    var.otel_collector_resources.memory_request == null ? {} : { memory = var.otel_collector_resources.memory_request },
  )

  otel_collector_resources = merge(
    length(local.otel_collector_resource_requests) > 0 ? { requests = local.otel_collector_resource_requests } : {},
    length(local.otel_collector_resource_limits) > 0 ? { limits = local.otel_collector_resource_limits } : {},
  )

  otel_collector_values = var.metrics_enabled ? templatefile("${path.module}/templates/otel_values.yaml.tpl", {
    name                  = local.otel_collector_name
    replica_count         = 1
    image_repository      = var.otel_collector_image_repository
    image_tag             = var.otel_collector_image_tag
    command_name          = var.otel_collector_command_name
    service_account       = var.otel_collector_service_account
    resources             = local.otel_collector_resources
    scrape_interval       = "${var.scrape_interval_seconds}s"
    amp_region            = local.amp_region
    remote_write_endpoint = local.amp_remote_write_endpoint

    kube_state_metrics_enabled = local.kube_state_metrics_install
    kube_state_metrics_target  = local.kube_state_metrics_target

    cadvisor_keep_regex         = local.metrics_cadvisor_keep_regex
    kube_state_keep_regex       = local.metrics_kube_state_keep_regex
    kubelet_resource_keep_regex = local.metrics_kubelet_resource_keep_regex
  }) : null
}

resource "helm_release" "otel_collector" {
  count = var.metrics_enabled ? 1 : 0

  name       = local.otel_collector_name
  namespace  = local.metrics_namespace
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_collector_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat([local.otel_collector_values], var.otel_collector_helm_values)

  depends_on = [
    # The collector reads AWS credentials on startup through the Pod Identity
    # Agent; without the association it falls back to the node role and every
    # remote write fails with AccessDenied.
    aws_eks_pod_identity_association.otel_collector,
    # Not a hard dependency — a missing target is a failed scrape, not a failed
    # collector — but it keeps the first minutes free of scrape errors.
    helm_release.kube_state_metrics,
  ]
}
