################################################################################
# Workload logs (Loki on S3 + Alloy) and the in-cluster Grafana
#
# Toggle matrix for the logs half of this module, plus the label contract the
# dashboard's LogQL layer is written against. Run from the module root:
# `tofu test`.
#
# Karpenter and the External Secrets Operator are off in every run: they pull in
# submodules and Helm releases that have nothing to do with what is asserted
# here, and leaving them on only slows the plan down.
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = {
      id     = "us-east-2"
      name   = "us-east-2"
      region = "us-east-2"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.gr7.us-east-2.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_prometheus_workspace" {
    defaults = {
      id  = "ws-11111111-2222-3333-4444-555555555555"
      arn = "arn:aws:aps:us-east-2:123456789012:workspace/ws-11111111-2222-3333-4444-555555555555"
    }
  }
}

mock_provider "helm" {}

variables {
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
  eso_enabled       = false
}

################################################################################
# Logs off — the default. No bucket, no Loki, no Alloy, no IAM.
################################################################################

run "logs_disabled_renders_nothing" {
  command = plan

  assert {
    condition     = length(module.loki_bucket) == 0
    error_message = "No log bucket may be created while logs_enabled is false"
  }

  assert {
    condition     = length(helm_release.loki) == 0 && length(helm_release.alloy) == 0
    error_message = "Neither Loki nor Alloy may be installed while logs_enabled is false"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.loki) == 0 && length(module.loki_role) == 0
    error_message = "No Loki identity may exist while logs_enabled is false"
  }

  assert {
    condition     = output.loki_endpoint == null && output.loki_namespace == null && output.loki_s3_bucket == null
    error_message = "Every Loki output must be null while logs_enabled is false"
  }

  assert {
    condition     = length(helm_release.grafana) == 0 && output.grafana_namespace == null
    error_message = "The in-cluster Grafana is off by default"
  }
}

################################################################################
# Logs on — bucket, identity, both releases, and the endpoint contract.
################################################################################

run "logs_enabled_creates_bucket_loki_and_alloy" {
  command = plan

  variables {
    logs_enabled = true
  }

  assert {
    condition     = length(module.loki_bucket) == 1
    error_message = "logs_enabled with no loki_s3_bucket must create one"
  }

  assert {
    condition     = output.loki_s3_bucket == "ravion-loki-test-cluster-123456789012"
    error_message = "The generated bucket name must be ravion-loki-<cluster>-<account>"
  }

  assert {
    condition     = output.loki_s3_bucket_arn == "arn:aws:s3:::ravion-loki-test-cluster-123456789012"
    error_message = "The bucket ARN must be constructed from the partition and the bucket name"
  }

  assert {
    condition     = length(helm_release.loki) == 1 && length(helm_release.alloy) == 1
    error_message = "logs_enabled must install both Loki and Alloy"
  }

  # In-cluster only: the endpoint is a ClusterIP Service URL, which is what
  # makes Beacon's tunnel the sole route to it.
  assert {
    condition     = output.loki_endpoint == "http://ravion-loki.ravion-beacon.svc.cluster.local:3100"
    error_message = "Loki's endpoint must be the in-cluster Service URL in Beacon's namespace"
  }

  assert {
    condition     = output.loki_namespace == "ravion-beacon"
    error_message = "Loki defaults to Beacon's namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.loki[0].service_account == var.loki_service_account
    error_message = "The Pod Identity association must bind to Loki's service account"
  }

  # Read, write, AND delete: delete is how the compactor enforces retention.
  assert {
    condition     = data.aws_iam_policy_document.loki_s3[0].statement[1].actions == toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"])
    error_message = "Loki must be able to delete objects, or retention never happens"
  }

  assert {
    condition     = data.aws_iam_policy_document.loki_s3[0].statement[1].resources == toset(["arn:aws:s3:::ravion-loki-test-cluster-123456789012/*"])
    error_message = "Loki's object grant must be scoped to the log bucket"
  }
}

################################################################################
# Bring your own bucket — creation suppressed, everything else still resolves.
################################################################################

run "byo_bucket_suppresses_creation" {
  command = plan

  variables {
    logs_enabled   = true
    loki_s3_bucket = "my-existing-log-bucket"
  }

  assert {
    condition     = length(module.loki_bucket) == 0
    error_message = "An explicit loki_s3_bucket must suppress bucket creation"
  }

  assert {
    condition     = output.loki_s3_bucket == "my-existing-log-bucket"
    error_message = "The bring-your-own bucket must flow through to the output"
  }

  assert {
    condition     = data.aws_iam_policy_document.loki_s3[0].statement[0].resources == toset(["arn:aws:s3:::my-existing-log-bucket"])
    error_message = "The Loki role must be scoped to the bring-your-own bucket"
  }

  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).loki.storage.bucketNames.chunks == "my-existing-log-bucket"
    error_message = "Loki must be configured against the bring-your-own bucket"
  }
}

################################################################################
# Retention — the compactor is the authority, the bucket is the backstop.
################################################################################

run "retention_is_enforced_in_both_places" {
  command = plan

  variables {
    logs_enabled       = true
    log_retention_days = 14
  }

  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).loki.limits_config.retention_period == "336h"
    error_message = "log_retention_days must reach Loki's limits_config as hours"
  }

  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).loki.compactor.retention_enabled == true
    error_message = "Retention does nothing in Loki unless the compactor is told to enforce it"
  }

  # A week later than the compactor, so it never races it into deleting an
  # index that is still being read.
  assert {
    condition     = local.loki_bucket_expiration_days == 21
    error_message = "The bucket lifecycle rule must expire a week after the retention period"
  }

  assert {
    condition     = output.log_retention_days == 14
    error_message = "The retention window must be published for the dashboard"
  }
}

################################################################################
# Loki topology — single binary, nothing else, no static credentials.
################################################################################

run "loki_runs_as_a_single_binary_with_no_extras" {
  command = plan

  variables {
    logs_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).deploymentMode == "SingleBinary"
    error_message = "Loki must be installed in single-binary mode"
  }

  assert {
    condition = alltrue([
      yamldecode(helm_release.loki[0].values[0]).backend.replicas == 0,
      yamldecode(helm_release.loki[0].values[0]).read.replicas == 0,
      yamldecode(helm_release.loki[0].values[0]).write.replicas == 0,
    ])
    error_message = "No simple-scalable target may have replicas alongside the single binary"
  }

  assert {
    condition = alltrue([
      yamldecode(helm_release.loki[0].values[0]).gateway.enabled == false,
      yamldecode(helm_release.loki[0].values[0]).chunksCache.enabled == false,
      yamldecode(helm_release.loki[0].values[0]).resultsCache.enabled == false,
      yamldecode(helm_release.loki[0].values[0]).minio.enabled == false,
    ])
    error_message = "The gateway, both memcached tiers, and the bundled MinIO must all be off"
  }

  # Structured metadata is where `level` lives; without this the schema rejects
  # it and the whole label design collapses into index labels.
  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).loki.limits_config.allow_structured_metadata == true
    error_message = "Structured metadata must be allowed"
  }

  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).loki.schemaConfig.configs[0].schema == "v13"
    error_message = "Only the v13 schema supports structured metadata"
  }

  # No keys anywhere: credentials come from the Pod Identity Agent.
  assert {
    condition     = !strcontains(helm_release.loki[0].values[0], "accessKeyId") && !strcontains(helm_release.loki[0].values[0], "secretAccessKey")
    error_message = "Loki must carry no static AWS credentials"
  }

  # An unschedulable PVC on a cluster with no CSI driver is a worse first run
  # than an ephemeral one.
  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).singleBinary.persistence.enabled == false
    error_message = "Loki persistence must be opt-in"
  }
}

################################################################################
# The label contract. Changing anything asserted here breaks the dashboard's
# LogQL layer, which is the point of asserting it.
################################################################################

run "alloy_attaches_the_agreed_label_set" {
  command = plan

  variables {
    logs_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.alloy[0].values[0]).controller.type == "daemonset"
    error_message = "Alloy must run on every node"
  }

  assert {
    condition = alltrue([
      for label in ["namespace", "app", "workload"] :
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "target_label  = \"${label}\"")
    ])
    error_message = "Alloy must attach exactly the namespace/app/workload labels the dashboard selects on"
  }

  # The cardinality rule the whole design rests on.
  assert {
    condition     = !strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "target_label  = \"pod\"")
    error_message = "Pod name must never be a Loki label: one stream per replica per restart is what kills a Loki"
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "stage.structured_metadata")
    error_message = "level must be attached as structured metadata, not as a label"
  }

  # loki.source.file adds a filename label containing the pod UID.
  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "stage.label_drop")
    error_message = "The filename label must be dropped or per-pod cardinality comes back through the side door"
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "url = \"http://ravion-loki.ravion-beacon.svc.cluster.local:3100/loki/api/v1/push\"")
    error_message = "Alloy must push to the in-cluster Loki"
  }
}

################################################################################
# Beacon's proxy allowlist — the only route from Ravion to Loki.
################################################################################

run "beacon_receives_the_loki_endpoint" {
  command = plan

  variables {
    logs_enabled   = true
    beacon_enabled = true
  }

  assert {
    condition     = length(local.beacon_log_proxy_values) == 1
    error_message = "Beacon must be handed a proxy allowlist document when logs are on"
  }

  assert {
    condition     = yamldecode(local.beacon_log_proxy_values[0]).httpProxy.allowedEndpoints == ["http://ravion-loki.ravion-beacon.svc.cluster.local:3100"]
    error_message = "Beacon's proxy allowlist must name exactly the Loki endpoint"
  }
}

run "beacon_gets_no_allowlist_without_logs" {
  command = plan

  variables {
    beacon_enabled = true
  }

  assert {
    condition     = length(local.beacon_log_proxy_values) == 0
    error_message = "With logs off there is nothing to proxy to, so no allowlist document is rendered"
  }
}

run "loki_alone_gives_beacon_nothing_to_proxy" {
  command = plan

  variables {
    logs_enabled = true
  }

  assert {
    condition     = length(local.beacon_log_proxy_values) == 0
    error_message = "Without Beacon there is no proxy to allowlist for"
  }
}

################################################################################
# In-cluster Grafana.
################################################################################

run "grafana_provisions_both_datasources" {
  command = plan

  variables {
    logs_enabled     = true
    metrics_enabled  = true
    amp_workspace_id = "ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    grafana_enabled  = true
  }

  assert {
    condition     = length(yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources) == 2
    error_message = "With both pipelines on, Grafana must be preprovisioned with both datasources"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources[0].jsonData.sigV4Auth == true
    error_message = "The AMP datasource must sign with SigV4"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources[0].jsonData.sigV4Region == "us-east-2"
    error_message = "The AMP datasource must sign for the workspace's region"
  }

  # SigV4 is off in Grafana by default and a datasource asking for it just
  # fails to authenticate, with no hint as to why.
  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].auth.sigv4_auth_enabled == true
    error_message = "SigV4 must be enabled in grafana.ini or the AMP datasource cannot authenticate"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources[1].url == "http://ravion-loki.ravion-beacon.svc.cluster.local:3100"
    error_message = "The Loki datasource must point at the in-cluster Service"
  }

  assert {
    condition     = output.grafana_amp_role_arn != null
    error_message = "Grafana needs its own Pod Identity role to query AMP"
  }
}

run "grafana_with_logs_only_has_one_datasource" {
  command = plan

  variables {
    logs_enabled    = true
    grafana_enabled = true
  }

  assert {
    condition     = length(yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources) == 1
    error_message = "A datasource whose pipeline is not installed must not be rendered"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources[0].type == "loki"
    error_message = "With metrics off, only the Loki datasource remains"
  }

  assert {
    condition     = length(module.grafana_workspace_read_role) == 0 && output.grafana_amp_role_arn == null
    error_message = "With no workspace to query there is nothing for the AMP role to grant"
  }
}
