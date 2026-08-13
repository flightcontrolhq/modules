// Grafana Alloy configuration, rendered by alloy.tf. Alloy syntax, not YAML.
//
// THE LABEL SET BELOW IS A CONTRACT. Ravion's log views build LogQL selectors
// on `namespace`, `app` and `workload`, and read `level` from structured
// metadata. Adding a label here is cheap to write and expensive to run: every
// distinct combination is a separate Loki stream, so a pod-name label turns one
// stream per workload into one per replica per restart. Anything
// high-cardinality belongs in structured metadata, which is stored but not
// indexed. Changing these names is a breaking change for the dashboard.

// Pods on THIS node only. Alloy runs as a DaemonSet, so an unfiltered
// discovery would have every instance watching every pod in the cluster and
// then discarding all but its own — the chart sets HOSTNAME from
// spec.nodeName, which is what makes the field selector possible.
discovery.kubernetes "pods" {
  role = "pod"

  selectors {
    role  = "pod"
    field = "spec.nodeName=" + sys.env("HOSTNAME")
  }
}

discovery.relabel "pod_logs" {
  targets = discovery.kubernetes.pods.targets

  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }

  // `app` prefers the recommended label but accepts the older bare one. Both
  // rules use a regex that only matches non-empty values, so a missing label
  // leaves whatever the previous rule set rather than blanking it.
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    regex         = "(.+)"
    target_label  = "app"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
    regex         = "(.+)"
    target_label  = "app"
  }

  // The controller name for a Deployment's pod is the ReplicaSet, whose name
  // is "<deployment>-<hash>". Stripping the hash gives the workload a human
  // named it, and keeps the label stable across rollouts.
  rule {
    source_labels = ["__meta_kubernetes_pod_controller_name"]
    regex         = "([0-9a-z-.]+?)(-[0-9a-f]{8,10})?"
    target_label  = "workload"
  }

  // Last resort for a pod with no app label at all: match only when `app` is
  // still empty (the leading separator), and copy `workload` into it.
  rule {
    source_labels = ["app", "workload"]
    separator     = ";"
    regex         = ";(.+)"
    replacement   = "$1"
    target_label  = "app"
  }

  // The kubelet writes every container's stdout under the pod's UID.
  rule {
    source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    action        = "replace"
    replacement   = "/var/log/pods/*$1/*.log"
    target_label  = "__path__"
  }
}

local.file_match "pod_logs" {
  path_targets = discovery.relabel.pod_logs.output
}

loki.source.file "pod_logs" {
  targets    = local.file_match.pod_logs.targets
  forward_to = [loki.process.pod_logs.receiver]
}

loki.process "pod_logs" {
  forward_to = [loki.write.ravion.receiver]

  // containerd writes CRI-format lines: "<ts> <stream> <flags> <message>".
  // This stage recovers the container's own timestamp, so a log's time is when
  // the application emitted it rather than when Alloy read the file.
  stage.cri {}

  // Best-effort severity. Structured metadata, not a label: the value is
  // useful to filter on and would be ruinous to index, because a stream would
  // then exist per level per workload and a single request's lines would be
  // split across several of them.
  stage.regex {
    expression = "(?i)\\b(?P<level>trace|debug|info|warn|warning|error|fatal|panic)\\b"
  }

  stage.structured_metadata {
    values = {
      level = "",
    }
  }

  // loki.source.file attaches the log file's path as a `filename` label. The
  // path contains the pod UID, so leaving it in place would reintroduce
  // exactly the per-pod cardinality this label set exists to avoid.
  stage.label_drop {
    values = ["filename"]
  }
}

loki.write "ravion" {
  endpoint {
    url = "${loki_push_url}"
  }
}
