################################################################################
# What Beacon may proxy a query to
#
# Ravion never dials into a cluster: the dashboard's Logs and Metrics tabs read
# a store by asking the agent to make the request from inside. Which URLs the
# agent will make a request to is an allowlist in its own Helm values, so it is
# something the customer reads in their own Terraform rather than something the
# control plane names at query time.
#
# Three kinds of destination end up on that list:
#
#   1. THE IN-CLUSTER STORES. Loki, and (from 0.8.1) the in-cluster Prometheus.
#      ClusterIP Services with no route out of the cluster at all, which is why
#      the agent is the only thing that can reach them.
#
#   2. EXTERNAL STORES RAVION RENDERS FROM. Grafana Cloud's query endpoints.
#      These are reachable from the internet, but the credential is not: it
#      lives in a Kubernetes Secret the agent reads, so a proxied query carries
#      an Authorization header the control plane never sees.
#
#   3. NOTHING ELSE. A ship-only vendor gets a link in the tab, not a proxy
#      entry — Ravion does not query Datadog on the customer's behalf.
#
# The credential entries name a Secret, never a value. Beacon attaches the
# Authorization header for requests under the matching prefix and forwards no
# caller-supplied one, which is the rule that keeps this from being an open
# proxy with the cluster's credentials attached.
################################################################################

locals {
  beacon_grafana_cloud_logs_secret_name    = "ravion-observability-grafana-cloud-logs"
  beacon_grafana_cloud_metrics_secret_name = "ravion-observability-grafana-cloud-metrics"

  # Materialized into Beacon's namespace, not the collectors': the agent mounts
  # them, and a Secret is not readable across namespaces.
  beacon_proxy_credential_secrets = concat(
    var.beacon_enabled && local.logs_grafana_cloud_enabled && local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_config.logs_user != null ? [{
      name      = local.beacon_grafana_cloud_logs_secret_name
      namespace = var.beacon_namespace
      template = {
        username = local.grafana_cloud_config.logs_user
        password = "{{ .token }}"
      }
      data = [{
        secretKey = "token"
        remoteRef = local.grafana_cloud_config.token_secret_arn
      }]
    }] : [],
    var.beacon_enabled && local.metrics_grafana_cloud_enabled && local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_config.metrics_user != null ? [{
      name      = local.beacon_grafana_cloud_metrics_secret_name
      namespace = var.beacon_namespace
      template = {
        username = local.grafana_cloud_config.metrics_user
        password = "{{ .token }}"
      }
      data = [{
        secretKey = "token"
        remoteRef = local.grafana_cloud_config.token_secret_arn
      }]
    }] : [],
  )

  # Prefixes, in the order the dashboard's fallback chain reads them.
  beacon_proxy_allowed_endpoints = compact(concat(
    [local.loki_enabled ? local.loki_endpoint : ""],
    [local.grafana_cloud_logs_query_url != null ? local.grafana_cloud_logs_query_url : ""],
    [local.grafana_cloud_metrics_query_url != null ? local.grafana_cloud_metrics_query_url : ""],
    [local.prometheus_endpoint != null ? local.prometheus_endpoint : ""],
  ))

  beacon_proxy_credentials = concat(
    local.grafana_cloud_logs_query_url != null && length([for secret in local.beacon_proxy_credential_secrets : secret if secret.name == local.beacon_grafana_cloud_logs_secret_name]) > 0 ? [{
      endpointPrefix = local.grafana_cloud_logs_query_url
      secretName     = local.beacon_grafana_cloud_logs_secret_name
      kind           = "basic"
    }] : [],
    local.grafana_cloud_metrics_query_url != null && length([for secret in local.beacon_proxy_credential_secrets : secret if secret.name == local.beacon_grafana_cloud_metrics_secret_name]) > 0 ? [{
      endpointPrefix = local.grafana_cloud_metrics_query_url
      secretName     = local.beacon_grafana_cloud_metrics_secret_name
      kind           = "basic"
    }] : [],
  )

  # The single name the control plane carries as `auth_secret` on a source it
  # proxies. Logs first: the Logs tab is the one that reaches an external store
  # in 0.8.x. beacon_proxy_credentials is the full mapping.
  observability_credentials_secret_name = length(local.beacon_proxy_credentials) > 0 ? local.beacon_proxy_credentials[0].secretName : null

  beacon_observability_proxy_values = var.beacon_enabled && length(local.beacon_proxy_allowed_endpoints) > 0 ? [
    yamlencode({
      httpProxy = {
        enabled          = true
        allowedEndpoints = local.beacon_proxy_allowed_endpoints
        credentials      = local.beacon_proxy_credentials
      }
    }),
  ] : []
}
