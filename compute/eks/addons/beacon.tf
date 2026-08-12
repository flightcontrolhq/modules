################################################################################
# Ravion Beacon (enrollment + Helm)
#
# Beacon is Ravion's in-cluster agent. It dials the control plane outbound over
# a single WebSocket — the control plane can never dial in, because a
# private-endpoint EKS API is reachable from nowhere else — and reports workload
# state. Deploying from inside the cluster is a separate, declined-by-default
# grant (beacon_deploy_enabled).
#
# Three things about the shape of this file, all forced by the API contract in
# packages/api-go/server/handlers/beacon_enrollment.go:
#
#   1. ENROLLMENT IS ONE CALL AND RETURNS THE CLIENT SECRET EXACTLY ONCE. WorkOS
#      mints it and cannot return it a second time, and Ravion stores no copy
#      and no hash. A re-run that enrolled again would 409, and a run that lost
#      the response would have destroyed the only copy — so the call is made
#      from a provisioner (apply-time, never plan-time) that first checks
#      whether a credential is already stored, and the response is written
#      straight into AWS Secrets Manager in the customer's own account.
#
#   2. THAT SECRETS MANAGER SECRET IS THE IDEMPOTENCY ANCHOR. It is what makes
#      "have we enrolled this cluster already?" a question Terraform can answer
#      on a fresh runner with no local state. It is also what lets a lost
#      Terraform state be recovered without rotating a live agent's credential.
#
#   3. TERRAFORM ENROLLS, NOT THE AGENT. Beacon only ever reads the Kubernetes
#      Secret and presents the pair over its existing WebSocket; the gateway
#      performs the WorkOS exchange server-side. That is what keeps Beacon's
#      RBAC free of every write verb and its egress down to one destination.
#      See docs/adr/beacon-workos-m2m-auth.md in the Ravion monorepo.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  beacon_cluster_arn = data.aws_eks_cluster.this.arn
  beacon_region      = coalesce(var.region, data.aws_region.current.region)

  # Names and keys the two charts must agree on. Both ends are wired from these
  # locals rather than from the charts' defaults so they cannot drift apart.
  beacon_k8s_secret_name   = "ravion-beacon-credential"
  beacon_client_id_key     = "clientId"
  beacon_client_secret_key = "clientSecret"

  # Deterministic, so a re-enable finds the credential it left behind rather
  # than enrolling a second identity for the same cluster.
  beacon_credential_secret_name = "ravion/beacon/${var.cluster_name}/credential"

  # An OCI reference names registry + chart in one string; the Helm provider
  # wants them split. A value that is not an OCI reference is treated as a
  # filesystem path to a chart directory, which is how the chart is tested
  # before it is published to ECR Public.
  beacon_chart_is_oci     = startswith(var.beacon_chart_source, "oci://")
  beacon_chart_repository = local.beacon_chart_is_oci ? regex("^(.*)/[^/]+$", var.beacon_chart_source)[0] : null
  beacon_chart_name       = local.beacon_chart_is_oci ? regex("^.*/([^/]+)$", var.beacon_chart_source)[0] : var.beacon_chart_source

  # The stored document is the enrollment response verbatim, envelope included,
  # so the shell that writes it needs no JSON parser and Terraform does the
  # decoding. Rotation returns the same shape, so replacing the stored value by
  # hand during a rotation needs no reshaping either.
  beacon_enrollment = var.beacon_enabled ? jsondecode(data.aws_secretsmanager_secret_version.beacon_credential[0].secret_string).data : null

  # The chart falls back to namespaceScope when deploy.namespaces is empty, so
  # the precondition below has to check the same fallback the chart will apply.
  beacon_deploy_namespaces_effective = length(var.beacon_deploy_namespaces) > 0 ? var.beacon_deploy_namespaces : var.beacon_namespace_scope
}

################################################################################
# Credential store
#
# The customer's own account holds the only copy of the client secret. Ravion
# has none: WorkOS returned the plaintext once, this module wrote it here and
# into the cluster, and nothing else ever sees it.
################################################################################

resource "aws_secretsmanager_secret" "beacon_credential" {
  count = var.beacon_enabled ? 1 : 0

  name        = local.beacon_credential_secret_name
  description = "Ravion Beacon WorkOS Connect M2M credential for EKS cluster ${var.cluster_name}. Written once at enrollment; the plaintext exists nowhere else."

  # No recovery window. The name is deterministic, so a 30-day window would
  # block re-enabling Beacon on this cluster for a month after disabling it —
  # and a revoked credential has no value worth recovering.
  recovery_window_in_days = 0

  tags = local.tags
}

################################################################################
# Enrollment
#
# A provisioner rather than a data source, deliberately: `data "external"` and
# `data "http"` run during plan, and enrolling a cluster during a plan the
# operator may never apply would leave an agent identity nobody installed.
################################################################################

resource "terraform_data" "beacon_enrollment" {
  count = var.beacon_enabled ? 1 : 0

  # Neither the API token nor the response is a trigger: the token is not
  # stored in state, and re-running the script is a no-op once a credential
  # exists.
  triggers_replace = {
    cluster_arn = local.beacon_cluster_arn
    secret_arn  = aws_secretsmanager_secret.beacon_credential[0].arn
    script      = "v1"
  }

  lifecycle {
    precondition {
      condition     = var.beacon_api_url != null && var.beacon_api_token != null
      error_message = "beacon_api_url and beacon_api_token are required when beacon_enabled is true. Both come from the Ravion control plane: the API base URL (the runner's RVN_API_URL, e.g. https://api.ravion.com/api/v1) and a runner JWT bearer token. The organization is taken from the token's claims and is never sent in the request."
    }
  }

  provisioner "local-exec" {
    quiet       = true
    interpreter = ["/bin/sh", "-c"]

    # Provisioner environment is not persisted to state, which is what keeps
    # the bearer token out of it.
    environment = {
      AWS_REGION           = local.beacon_region
      RVN_BEACON_API_URL   = var.beacon_api_url
      RVN_BEACON_API_TOKEN = var.beacon_api_token
      RVN_BEACON_SECRET_ID = aws_secretsmanager_secret.beacon_credential[0].arn
      RVN_BEACON_REQUEST = jsonencode({
        data = merge(
          {
            clusterArn  = local.beacon_cluster_arn
            clusterName = var.cluster_name
            region      = local.beacon_region
            capabilities = {
              execAllowed       = var.beacon_exec_enabled
              selfUpdateAllowed = var.beacon_self_update_enabled
              namespaceScope    = var.beacon_namespace_scope
            }
          },
          var.beacon_project_id == null ? {} : { projectId = var.beacon_project_id },
          var.beacon_environment_id == null ? {} : { environmentId = var.beacon_environment_id },
          var.beacon_aws_account_id == null ? {} : { awsAccountId = var.beacon_aws_account_id },
        )
      })
    }

    command = <<-EOT
      set -eu
      umask 077

      log() {
        printf '%s\n' "Beacon enrollment: $*"
      }

      require_command() {
        if ! command -v "$1" >/dev/null 2>&1; then
          echo "Missing required command for Beacon enrollment: $1" >&2
          exit 1
        fi
      }

      require_command aws
      require_command curl

      WORKDIR=""

      cleanup() {
        status=$?
        if [ -n "$WORKDIR" ]; then
          rm -rf "$WORKDIR"
        fi
        if [ "$status" -ne 0 ]; then
          printf '%s\n' "Beacon enrollment: failed with exit code $status" >&2
        fi
      }

      trap cleanup EXIT

      # The client secret is returned exactly once, so an already-stored value
      # is the only copy that will ever exist. Never enroll over it.
      if aws secretsmanager get-secret-value \
           --secret-id "$RVN_BEACON_SECRET_ID" \
           --query SecretString \
           --output text 2>/dev/null | grep -q 'workosClientSecret'; then
        log "credential already present; nothing to do"
        exit 0
      fi

      WORKDIR="$(mktemp -d)"

      # The bearer token goes in a curl config file rather than on the argument
      # list, where every other process on the runner could read it.
      printf 'header = "Authorization: Bearer %s"\n' "$RVN_BEACON_API_TOKEN" > "$WORKDIR/curl.cfg"

      log "enrolling cluster"

      status_code="$(
        printf '%s' "$RVN_BEACON_REQUEST" | curl \
          --silent \
          --show-error \
          --config "$WORKDIR/curl.cfg" \
          --header 'Content-Type: application/json' \
          --request POST \
          --data-binary @- \
          --output "$WORKDIR/response.json" \
          --write-out '%%{http_code}' \
          "$RVN_BEACON_API_URL/internal/beacon/agents"
      )"

      case "$status_code" in
        200)
          ;;
        409)
          echo "Beacon enrollment: this cluster already has a live agent identity, but no credential is stored in $RVN_BEACON_SECRET_ID." >&2
          echo "The client secret is returned exactly once and cannot be re-read. Either rotate it (POST /internal/beacon/client-secrets) and write the response document into that secret, or revoke the agent (POST /internal/beacon/revocations) and apply again." >&2
          exit 1
          ;;
        *)
          echo "Beacon enrollment: POST /internal/beacon/agents returned HTTP $status_code" >&2
          # Safe to echo: a non-200 body is an error envelope, never a credential.
          cat "$WORKDIR/response.json" >&2 2>/dev/null || true
          echo >&2
          exit 1
          ;;
      esac

      if ! grep -q 'workosClientSecret' "$WORKDIR/response.json"; then
        echo "Beacon enrollment: enrollment reported success but the response carried no workosClientSecret." >&2
        exit 1
      fi

      # file:// keeps the plaintext off the argument list, same reason as above.
      aws secretsmanager put-secret-value \
        --secret-id "$RVN_BEACON_SECRET_ID" \
        --secret-string "file://$WORKDIR/response.json" \
        --query VersionId \
        --output text > /dev/null

      log "credential stored"
    EOT
  }
}

# Deferred to apply on the first run, because the version it reads is written by
# the provisioner above. On every later plan the version already exists and is
# read normally, which is what makes a re-apply a no-op rather than a rotation.
data "aws_secretsmanager_secret_version" "beacon_credential" {
  count = var.beacon_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.beacon_credential[0].arn

  depends_on = [terraform_data.beacon_enrollment]
}

################################################################################
# Credential Secret
#
# Delivered as a local chart because the Helm provider is the only Kubernetes
# access this stack has, and because the beacon chart deliberately does not
# create this object: Beacon holds no RBAC on Secrets, so the kubelet reads it
# and projects it into the container.
################################################################################

resource "helm_release" "beacon_credential" {
  count = var.beacon_enabled ? 1 : 0

  name      = "ravion-beacon-credential"
  namespace = var.beacon_namespace
  chart     = "${path.module}/charts/beacon-credential"

  create_namespace = true
  upgrade_install  = true

  # sensitive() covers the whole document rather than the client secret alone:
  # this chart carries nothing that is worth showing in a plan, and marking the
  # element is what keeps the secret out of plan output and CI logs.
  values = [
    sensitive(yamlencode({
      secretName      = local.beacon_k8s_secret_name
      clientIdKey     = local.beacon_client_id_key
      clientSecretKey = local.beacon_client_secret_key
      clientId        = local.beacon_enrollment.workosClientId
      clientSecret    = local.beacon_enrollment.workosClientSecret
    })),
  ]
}

################################################################################
# Beacon agent
################################################################################

resource "helm_release" "beacon" {
  count = var.beacon_enabled ? 1 : 0

  name       = "ravion-beacon"
  namespace  = var.beacon_namespace
  repository = local.beacon_chart_repository
  chart      = local.beacon_chart_name
  version    = var.beacon_chart_version

  upgrade_install = true

  values = concat(
    [
      yamlencode({
        # The chart refuses to render without all three.
        cluster = {
          arn    = local.beacon_cluster_arn
          name   = var.cluster_name
          region = local.beacon_region
        }
        controlPlane = {
          endpoint = var.beacon_endpoint
        }
        credential = {
          secretName      = local.beacon_k8s_secret_name
          clientIdKey     = local.beacon_client_id_key
          clientSecretKey = local.beacon_client_secret_key
        }
        # Empty is cluster-wide observation. Non-empty renders no ClusterRole at
        # all — one namespaced Role per entry instead — which is the difference
        # between a restriction Ravion promises and one Kubernetes enforces.
        namespaceScope = var.beacon_namespace_scope
        exec = {
          enabled = var.beacon_exec_enabled
        }
        selfUpdate = {
          enabled = var.beacon_self_update_enabled
        }
        # The widest grant this chart can create, and off by default. Bounded by
        # the namespace list, which Kubernetes enforces; there is deliberately
        # no cluster-wide posture, so an empty list with deploy on fails the
        # render rather than granting cluster-wide write. yamlencode produces a
        # genuine empty list here, avoiding the `--set deploy.namespaces={}`
        # trap that yields a list containing one empty string.
        deploy = {
          enabled    = var.beacon_deploy_enabled
          namespaces = var.beacon_deploy_namespaces
        }
      }),
    ],
    var.beacon_helm_values,
  )

  # The image tag is the one value the control plane owns: Beacon patches its
  # own Deployment to roll the fleet forward, and an apply that re-asserted the
  # tag would revert every staged rollout. It is passed through `set`, which
  # holds nothing else, so ignore_changes below names exactly it. The chart's
  # tag is a FLOOR, not the truth (beacon ADR §6).
  set = var.beacon_image_tag == null ? [] : [
    {
      name  = "image.tag"
      value = var.beacon_image_tag
    },
  ]

  # The Secret must exist before the pod starts; it is mounted, not read
  # through the API, so a missing one is a container that never runs.
  depends_on = [helm_release.beacon_credential]

  lifecycle {
    # Everything except the image tag. See the comment on `set` above.
    ignore_changes = [set]

    precondition {
      condition     = !var.beacon_deploy_enabled || length(local.beacon_deploy_namespaces_effective) > 0
      error_message = "beacon_deploy_enabled is true but neither beacon_deploy_namespaces nor beacon_namespace_scope names a namespace. The chart refuses to render a cluster-wide deploy grant, by design: there is no 'deploy everywhere' posture, because the failure mode is an agent that can delete workloads in namespaces nobody meant to hand it."
    }
  }
}
