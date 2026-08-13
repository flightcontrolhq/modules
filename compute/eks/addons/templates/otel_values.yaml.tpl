# Helm values for the community opentelemetry-collector chart, rendered by
# otel_collector.tf. Structured values are emitted with jsonencode() because
# JSON is valid YAML — it keeps regexes and resource maps out of the business of
# YAML quoting and indentation.
#
# Chart defaults are removed by setting them to null, which is how Helm deletes
# a key a chart shipped. That is why the receivers, exporters and pipelines this
# collector does not use appear here at all: the chart's default config accepts
# OTLP, Jaeger and Zipkin and exports to debug, and a merge alone would leave
# all of it running.
mode: deployment
replicaCount: ${replica_count}
fullnameOverride: ${jsonencode(name)}

image:
  repository: ${jsonencode(image_repository)}
  tag: ${jsonencode(image_tag)}

# The chart renders this as `/<name>`. The ADOT image's entrypoint is
# /awscollector, not the upstream otelcol-contrib.
command:
  name: ${jsonencode(command_name)}

serviceAccount:
  create: true
  name: ${jsonencode(service_account)}

# Scraping the kubelet through the API server proxy needs nodes/proxy; the node
# service discovery needs nodes. Nothing here reads pods, services or secrets.
clusterRole:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["nodes", "nodes/proxy", "nodes/metrics"]
      verbs: ["get", "list", "watch"]

resources: ${jsonencode(resources)}

# Nothing sends telemetry to this collector — it pulls. No Service, and none of
# the chart's default receiver ports.
service:
  enabled: false

ports:
  otlp:
    enabled: false
  otlp-http:
    enabled: false
  jaeger-compact:
    enabled: false
  jaeger-thrift:
    enabled: false
  jaeger-grpc:
    enabled: false
  zipkin:
    enabled: false
  metrics:
    enabled: false

config:
  receivers:
    jaeger: null
    zipkin: null
    otlp: null
    prometheus:
      config:
        scrape_configs:
          # cAdvisor, reached through the API server proxy rather than the
          # kubelet's own address: the collector then needs no network path to
          # port 10250 on every node, which is what makes this work on
          # private-endpoint clusters and with restrictive node security groups.
          - job_name: kubernetes-cadvisor
            scrape_interval: ${scrape_interval}
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            authorization:
              type: Bearer
              credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
              - role: node
            relabel_configs:
              - source_labels: [__meta_kubernetes_node_name]
                target_label: node
              - target_label: __address__
                replacement: kubernetes.default.svc:443
              - source_labels: [__meta_kubernetes_node_name]
                regex: (.+)
                target_label: __metrics_path__
                replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
            metric_relabel_configs:
              # Drop everything outside the curated set before it enters
              # collector memory. `up` is exempt from metric_relabel_configs by
              # design, but is listed so the intent survives a reader.
              - source_labels: [__name__]
                regex: ${jsonencode(cadvisor_keep_regex)}
                action: keep
              # cAdvisor emits pod-level aggregates on the pause container with
              # an empty `container` label, which double-counts CPU and memory.
              # Network counters live on exactly those series, so the drop names
              # the families it applies to instead of dropping every empty one.
              - source_labels: [container, __name__]
                separator: ";"
                regex: ";container_(cpu|memory|oom)_.+"
                action: drop
              # The three labels that make cAdvisor expensive: `id` and `name`
              # carry the cgroup path and runtime container name, `image` the
              # full image reference with digest. All three change on every
              # restart and none is queried.
              - regex: id|name|image
                action: labeldrop
%{ if kube_state_metrics_enabled ~}
          # kube-state-metrics: a plain in-cluster target, so no service
          # discovery and no RBAC on services or endpoints.
          - job_name: kube-state-metrics
            scrape_interval: ${scrape_interval}
            static_configs:
              - targets: [${jsonencode(kube_state_metrics_target)}]
            metric_relabel_configs:
              - source_labels: [__name__]
                regex: ${jsonencode(kube_state_keep_regex)}
                action: keep
%{ endif ~}
          # The kubelet's summary API in Prometheus form: node CPU and memory
          # without a node-exporter DaemonSet.
          - job_name: kubernetes-nodes
            scrape_interval: ${scrape_interval}
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            authorization:
              type: Bearer
              credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
              - role: node
            relabel_configs:
              - source_labels: [__meta_kubernetes_node_name]
                target_label: node
              - target_label: __address__
                replacement: kubernetes.default.svc:443
              - source_labels: [__meta_kubernetes_node_name]
                regex: (.+)
                target_label: __metrics_path__
                replacement: /api/v1/nodes/$1/proxy/metrics/resource
            metric_relabel_configs:
              - source_labels: [__name__]
                regex: ${jsonencode(kubelet_resource_keep_regex)}
                action: keep

  processors:
    # Sized as a percentage of the container's memory limit, which is why
    # otel_collector_resources sets one by default.
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25
    batch: {}

  exporters:
    debug: null
    prometheusremotewrite:
      endpoint: ${jsonencode(remote_write_endpoint)}
      auth:
        authenticator: sigv4auth
      # AMP rejects samples older than an hour; retrying past that only burns
      # the queue, so failures are dropped rather than blocking newer batches.
      retry_on_failure:
        enabled: true
        initial_interval: 5s
        max_interval: 30s
        max_elapsed_time: 300s
      resource_to_telemetry_conversion:
        enabled: false

  extensions:
    # Credentials come from the Pod Identity Agent through the SDK's default
    # chain — the extension configures none of its own.
    sigv4auth:
      region: ${jsonencode(amp_region)}
      service: aps

  service:
    # health_check is the chart's readiness and liveness probe; removing it
    # fails the pod, not just the extension.
    extensions:
      - health_check
      - sigv4auth
    pipelines:
      logs: null
      traces: null
      metrics:
        receivers:
          - prometheus
        processors:
          - memory_limiter
          - batch
        exporters:
          - prometheusremotewrite
