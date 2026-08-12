# EKS Add-ons

Selectable add-ons for an existing EKS cluster, each toggled independently:

| Add-on | Toggle | Default | What it creates |
|---|---|---|---|
| **Karpenter** | `karpenter_enabled` | `true` | Controller + node IAM roles, Pod Identity association, instance profile, EKS access entry, SQS interruption queue, EventBridge rules (via `modules/eks_karpenter`), plus the `karpenter-crd` and `karpenter` Helm charts and an optional default NodePool |
| **AWS Load Balancer Controller** | automatic with any load balancer, or `lb_controller_enabled` opt-in | `false` | `aws-load-balancer-controller` Helm chart wired to the Pod Identity role created by the `compute/eks` composite; registers workload pods into shared load balancer target groups (`TargetGroupBinding`); Ingress → ALB, LoadBalancer Service → NLB |
| **External Secrets Operator** | `eso_enabled` | `true` | `external-secrets` Helm chart + Pod Identity role scoped to Secrets Manager / Parameter Store reads, plus the cluster-scoped `ravion-aws` and `ravion-aws-parameter-store` `ClusterSecretStore`s |
| **EBS CSI driver** | `ebs_csi_driver_enabled` | `false` | `aws-ebs-csi-driver` EKS add-on + Pod Identity role |
| **Container Insights** | `cloudwatch_observability_enabled` | `true` | `amazon-cloudwatch-observability` EKS add-on + Pod Identity role (CloudWatch agent + Fluent Bit) |
| **Ravion Beacon** | `beacon_enabled` | `false` | Enrolls the cluster with the Ravion control plane, stores the returned WorkOS Connect M2M credential in an AWS Secrets Manager secret and in a Kubernetes `Secret` (local `charts/beacon-credential`), and installs the `beacon` Helm chart — an in-cluster agent that dials Ravion outbound over a single WebSocket |
| **Shared load balancers** | `public_alb_enabled`, `private_alb_enabled`, `public_nlb_enabled`, `private_nlb_enabled` | `false` | Terraform-managed ALBs/NLBs (via `networking/alb` and `networking/nlb`) that workloads attach to with the load balancer controller's `TargetGroupBinding` CRD, plus cluster security group ingress rules allowing each load balancer to reach pods |

The [`compute/eks`](..) composite intentionally creates none of these, so clusters only carry what they use. EBS CSI and Container Insights are native EKS add-ons installed purely through the AWS API. Karpenter, the AWS Load Balancer Controller, the External Secrets Operator, and Beacon additionally install Helm charts, which are the only parts that need Kubernetes API connectivity.

> **Connectivity contract (Helm add-ons only):** the machine running Terraform must be able to reach the cluster's Kubernetes API endpoint. For private-endpoint clusters, run inside the cluster VPC with the composite's Ravion Runner security group (`ravion_runner_security_group_id` output) attached, and have the AWS CLI on PATH for `aws eks get-token`. With `karpenter_enabled`, `eso_enabled`, `lb_controller_enabled`, `beacon_enabled`, and all four load balancer toggles off, no cluster connectivity is needed. `beacon_enabled` additionally requires `curl` on PATH and reachability to the Ravion API, because enrollment is an HTTP call made during apply.
>
> **Authentication:** set `ravion_runner_role_arn` to the cluster's Ravion Runner role (`ravion_runner_role_arn` output of `compute/eks`) and `aws eks get-token` assumes it — the cluster module registers that role as an EKS access entry with cluster-admin, so per-run pipeline roles never need their own access entries. When null, the identity running Terraform is used directly and must already have cluster access.

## Usage

```hcl
module "eks_addons" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks/addons?ref=main"

  cluster_name = module.eks.cluster_name
  region       = "us-east-2"

  # Karpenter (default on) needs node placement wiring and cluster access
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_subnet_ids           = module.eks.node_subnet_ids
  ravion_runner_role_arn    = module.eks.ravion_runner_role_arn

  ebs_csi_driver_enabled = true

  # External Secrets Operator (default on) — narrow the read scope from
  # "everything in this account and region" to one prefix
  eso_secret_arns = ["arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/*"]

  # Shared public ALB that web workloads bind to via TargetGroupBinding
  public_alb_enabled          = true
  public_alb_https_enabled    = true
  public_alb_certificate_arns = [aws_acm_certificate.main.arn]
  public_subnet_ids           = module.network.public_subnet_ids
}
```

> **Pinning a `ref`:** this repository has no `vX.Y.Z` tags. Releases are tagged
> per module definition as `rvn-<definition-type>@<x.y.z>` (for example
> `rvn-aws-network@1.0.1`). Once a release of this stack is cut, pin to
> `?ref=rvn-eks-addons@<x.y.z>`; until then use `?ref=main` or a commit SHA.

### Shared load balancers

The shared load balancers mirror the ECS Cluster module's pattern: one Terraform-managed ALB (or NLB) is shared by many workloads. A workload module creates its own target group and listener rule, then registers pods with the target group in-cluster via the AWS Load Balancer Controller's [`TargetGroupBinding`](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/targetgroupbinding/targetgroupbinding/) CRD — enabling any load balancer therefore installs the controller automatically.

Placement and security wiring:

- Public ALB/NLB launch into `public_subnet_ids` (required when either public load balancer is enabled).
- Private ALB/NLB launch into `node_subnet_ids`.
- Each load balancer's security group is granted ingress to `cluster_security_group_id` on all TCP ports, so registered pods are reachable on any container port.

### Secrets (External Secrets Operator)

Kubernetes has no equivalent of the ECS task definition's `valueFrom` injection, so this add-on installs the [External Secrets Operator](https://external-secrets.io/) as the bridge. Workloads reference a Secrets Manager secret or SSM parameter **by ARN**; the operator reads it with its own Pod Identity credentials and materializes it into a Kubernetes Secret in the workload's namespace. Secret values never pass through Terraform state, Helm values, or Helm release history.

**Contract for workload charts.** The stores are cluster-scoped, so a chart in any namespace references them by name with no per-namespace setup:

| Backend | `secretStoreRef.name` | `secretStoreRef.kind` | `apiVersion` |
|---|---|---|---|
| AWS Secrets Manager | `ravion-aws` (`eso_secrets_manager_store_name`) | `ClusterSecretStore` | `external-secrets.io/v1` |
| AWS SSM Parameter Store | `ravion-aws-parameter-store` (`eso_parameter_store_store_name`) | `ClusterSecretStore` | `external-secrets.io/v1` |

There are two stores because ESO's AWS provider takes a single `service` per store — Secrets Manager and Parameter Store cannot share one. `ravion-aws` is the Secrets Manager store, which is the name Ravion app charts default to; charts select the Parameter Store variant only for `ssm` references. Both names are outputs (`eso_secrets_manager_store_name`, `eso_parameter_store_store_name`), so charts should read them rather than hardcode.

A workload's `ExternalSecret` then looks like:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-service
spec:
  secretStoreRef:
    name: ravion-aws
    kind: ClusterSecretStore
  target:
    name: my-service-env
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/db-AbCdEf
        property: password # optional JSON-key extraction, ECS `::jsonkey::` parity
```

**IAM scoping.** The operator's Pod Identity role grants `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret`, `ssm:GetParameter`, and `ssm:GetParameters`. Because workload secrets are created long after this stack applies, the default resource scope is every secret and parameter **in this account and region**. Set `eso_secret_arns` to narrow it to specific ARNs or prefixes — or to reach other regions and accounts, which the default deliberately excludes. Secrets encrypted with a customer-managed KMS key additionally need that key listed in `eso_kms_key_arns`; the AWS-managed `aws/secretsmanager` and `aws/ssm` keys need no explicit grant.

**At rest.** The values themselves live only in AWS Secrets Manager / Parameter Store, encrypted with KMS there. The Kubernetes Secrets the operator materializes are stored in etcd under **KMS envelope encryption**, which the [`compute/eks`](..) cluster module enables by default (`secrets_encryption_enabled`, `true`, creating a dedicated CMK per cluster unless `secrets_kms_key_arn` is supplied). Materialized Secrets are still readable by anything with Secret read RBAC in that namespace; mounting values as files via the [AWS Secrets Store CSI driver](https://github.com/aws/secrets-store-csi-driver-provider-aws), which skips the Kubernetes Secret object entirely, is a future hardening option not implemented here.

### Ravion Beacon

Beacon is Ravion's in-cluster agent. It dials the control plane **outbound** over a single WebSocket — the control plane can never dial in, because a private-endpoint EKS API is reachable from nowhere else — and reports workload state. Optionally, and separately, it can perform Ravion's Helm deploys from inside the cluster.

Off by default. `beacon_enabled = true` does three things in one apply:

1. **Enrolls** the cluster with the Ravion API, which provisions a per-cluster WorkOS Connect M2M application and returns a `client_id` + `client_secret` pair.
2. **Stores** that pair — in an AWS Secrets Manager secret in *your* account (`ravion/beacon/<cluster>/credential`) and in a Kubernetes `Secret` named `ravion-beacon-credential` in `beacon_namespace`, under the keys `clientId` and `clientSecret`.
3. **Installs** the agent chart, wired to that Secret.

```hcl
module "eks_addons" {
  # ...
  beacon_enabled   = true
  beacon_api_url   = "https://api.ravion.com/api/v1" # same base URL as the runner's RVN_API_URL
  beacon_api_token = var.ravion_runner_token         # runner JWT; sensitive

  # Optional: bound what the agent can see to the namespaces Ravion deploys into
  beacon_namespace_scope = ["app-prod", "app-stg"]
}
```

#### The credential, and why it is stored twice

The client secret is minted by WorkOS and returned **exactly once**. Ravion keeps no copy and no hash of it — after this call there is no column in Ravion's database a Beacon secret could be written to. So this module cannot re-fetch it, and a second enrollment call for the same cluster is refused with `409`.

That is why enrollment writes into Secrets Manager. It gives the module a durable, account-local answer to "has this cluster already been enrolled?", which is what makes a re-apply on a fresh runner a no-op instead of a `409`, and what lets a **lost Terraform state be recovered without rotating a live agent's credential**. The stored document is the API response verbatim, envelope included, so a hand-run rotation can be pasted into it without reshaping.

The enrollment call runs from an apply-time provisioner, never a data source: `data "http"` and `data "external"` execute during **plan**, and enrolling a cluster during a plan nobody applies would leave an agent identity that no cluster is running.

The runner therefore needs, in addition to the existing AWS-CLI-on-PATH requirement, **`curl` on PATH** and IAM permission to `secretsmanager:CreateSecret`, `GetSecretValue`, `PutSecretValue`, `DescribeSecret`, `TagResource` and `DeleteSecret` on that secret.

**The client secret is never an output.** `beacon_client_id` and `beacon_agent_id` are — both are opaque identifiers the API documents as safe to expose (the client id is the `sub` claim of every token minted for this agent, not a credential).

#### Testing before the public chart exists

Two overrides, both designed for exactly this:

```hcl
# A chart directory on disk instead of the ECR Public reference. Anything that
# is not an `oci://` reference is treated as a filesystem path.
beacon_chart_source = "/path/to/ravion/packages/beacon/chart/beacon"

# A gateway on your own machine instead of the production endpoint. Reachable
# from inside the cluster, so a tunnel or an in-cluster address, not localhost.
beacon_endpoint = "ws://host.docker.internal:3001/beacon/v1/connect"

# And point enrollment at your local API
beacon_api_url = "http://localhost:3001/api/v1"
```

`beacon_chart_version` is ignored for a filesystem chart. Note that `beacon_chart_source` must stay **publicly pullable** in production: customer clusters cannot pull from Ravion's private ECR.

#### The image tag is not Terraform's to own

With `beacon_self_update_enabled` on (the default), the control plane rolls each cluster's agent forward by patching Beacon's own Deployment — a namespaced `Role` scoped by `resourceNames` to that one object, and the only write permission the chart creates by default. An apply that re-asserted the image tag would revert every staged rollout, so the release carries:

```hcl
set = [{ name = "image.tag", value = var.beacon_image_tag }]

lifecycle {
  ignore_changes = [set]
}
```

`set` carries the image tag and nothing else, so ignoring it ignores exactly the tag. `beacon_image_tag` is therefore a **floor, not a pin**: a fresh install starts there and the control plane moves it forward. Consequences worth knowing:

- **Changing `beacon_image_tag` on an existing release does nothing.** Replace the release (`tofu apply -replace='module.eks_addons.helm_release.beacon[0]'`) to move the floor.
- **To make Terraform the single owner of the version instead**, set `beacon_self_update_enabled = false`, set `beacon_image_tag` explicitly, and remove the `ignore_changes` in `beacon.tf`. You then own keeping the agent current — Ravion supports two agent minor versions back.
- The running version is reported in every heartbeat, so a cluster stuck on an old build is visible in fleet health rather than discovered during an incident.

#### Namespace scoping and the deploy grant

`beacon_namespace_scope` is the one value that turns a cluster-wide component into a bounded one, and it is enforced by Kubernetes rather than by the agent: non-empty renders **no observation ClusterRole at all**, one namespaced `Role`/`RoleBinding` per entry instead. A scoped install can read no `nodes` and no `namespaces`, so the node count in fleet health is reported as unknown; nothing else changes.

`beacon_deploy_enabled` is the widest grant the chart can create and is off by default. In the namespaces it covers, Beacon can create, update and delete Deployments, Services, Jobs, Ingresses and Secrets. It can never create anything in `rbac.authorization.k8s.io`, no `namespaces`, and nothing cluster-scoped — so it cannot widen itself. It is bounded by `beacon_deploy_namespaces`, falling back to `beacon_namespace_scope`; **if both are empty the apply fails**, because there is deliberately no "deploy everywhere" posture. Declining it leaves a fully working agent and Ravion deploys to the cluster from outside as it always has.

Values this module does not surface directly — `portForward.enabled`, `helmInventory.enabled`, `redaction.extraPatterns`, `image.repository`, resources, tolerations — go through `beacon_helm_values`. Read the chart's `README.md` before enabling any of the opt-in capabilities.

#### Rotating and revoking

| Situation | What to do |
|---|---|
| **Routine rotation** | `POST {beacon_api_url}/internal/beacon/client-secrets` with `{"data":{"beaconAgentId":"<beacon_agent_id output>"}}` and a runner JWT. Write the response document verbatim into the Secrets Manager secret (`beacon_credential_secret_arn` output), then apply. The Kubernetes Secret is replaced from it. The outgoing secret stays live by default so there is no reconnect gap; it is pruned by the *next* rotation. |
| **Compromised secret** | Same call with `"revokeOutgoing": true`. The old secret stops working immediately and the agent reconnects with the new one. |
| **Credential lost, agent still enrolled** | Enrollment returns `409` and the apply stops with a message saying so. Rotate as above, or revoke and re-apply — the secret cannot be re-read, ever. |
| **Stop the agent now, without touching Terraform** | Ravion's kill switch. `POST {beacon_api_url}/internal/beacon/revocations` deletes the WorkOS application and sets `disabledAt`: no token can be minted afterwards by anyone holding any secret, and the live connection is closed. A disabled agent that reconnects is still admitted and then immediately handed its disable directive, so re-enabling never requires a customer to run `helm upgrade` during an incident. |
| **Offboard permanently** | Revoke as above, then `beacon_enabled = false` and apply. That removes both Helm releases (the agent and its Secret) and deletes the Secrets Manager secret with no recovery window — the name is deterministic, so a 30-day window would block re-enabling Beacon on this cluster for a month. |

Disabling the flag alone does **not** revoke the identity: it removes the installation, not the WorkOS application. Revoke first if the cluster is going away.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |
| helm               | >= 3.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the existing EKS cluster. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| tags | Tags applied to created resources and Karpenter-launched instances. | `map(string)` | `{}` | no |
| karpenter_enabled | Install Karpenter end to end. | `bool` | `true` | no |
| ravion_runner_role_arn | IAM role assumed by `aws eks get-token` for Kubernetes API authentication. | `string` | `null` | no |
| lb_controller_enabled | Install the AWS Load Balancer Controller without any shared load balancer (it installs automatically with one). | `bool` | `false` | no |
| lb_controller_chart_version | aws-load-balancer-controller chart version. | `string` | `"1.14.0"` | no |
| lb_controller_namespace / lb_controller_service_account | Must match the Pod Identity association from `compute/eks`. | `string` | `"kube-system"` / `"aws-load-balancer-controller"` | no |
| lb_controller_helm_values | Extra YAML docs merged into the chart values. | `list(string)` | `[]` | no |
| karpenter_controller_namespace | Namespace for the controller and its Pod Identity association. | `string` | `"kube-system"` | no |
| karpenter_controller_service_account | Service account for the controller and its Pod Identity association. | `string` | `"karpenter"` | no |
| karpenter_chart_version | Karpenter (and karpenter-crd) chart version. | `string` | `"1.14.0"` | no |
| karpenter_node_role_additional_managed_policy_arns | Extra managed policies on the Karpenter node role. | `list(string)` | `[]` | no |
| karpenter_interruption_queue_name | Override interruption queue name (`karpenter-<cluster>` when null). | `string` | `null` | no |
| karpenter_interruption_queue_message_retention_seconds | Interruption queue retention. | `number` | `300` | no |
| karpenter_helm_values | Extra YAML docs merged into the Karpenter chart values. | `list(string)` | `[]` | no |
| karpenter_default_node_pool_enabled | Create the default NodePool + EC2NodeClass. | `bool` | `true` | no |
| node_subnet_ids | Private subnets for the default NodePool and internal load balancers. Required when Karpenter's default NodePool, the private ALB, or the private NLB is enabled. | `list(string)` | `null` | no |
| cluster_security_group_id | Cluster security group for Karpenter nodes and load-balancer-to-pod ingress. Required when Karpenter's default NodePool or any shared load balancer is enabled. | `string` | `null` | no |
| karpenter_default_node_pool | Default NodePool settings (capacity types, categories, arch, CPU limit, expiry). | `object` | `{}` | no |
| eso_enabled | Install the External Secrets Operator, its Pod Identity role, and the Ravion ClusterSecretStores. | `bool` | `true` | no |
| eso_chart_version | external-secrets chart version. | `string` | `"2.8.0"` | no |
| eso_namespace | Namespace the operator is installed into (created if missing). | `string` | `"external-secrets"` | no |
| eso_service_account | Controller service account; must match the Pod Identity association. | `string` | `"external-secrets"` | no |
| eso_secret_arns | Secrets Manager / SSM ARNs (wildcards allowed) the operator may read. Empty means account- and region-wide read. | `list(string)` | `[]` | no |
| eso_kms_key_arns | Customer-managed KMS keys the operator may decrypt with. | `list(string)` | `[]` | no |
| eso_cluster_secret_stores_enabled | Create the Ravion ClusterSecretStores. | `bool` | `true` | no |
| eso_secrets_manager_store_name | Name of the cluster-scoped Secrets Manager store (the app-chart default). | `string` | `"ravion-aws"` | no |
| eso_parameter_store_store_name | Name of the cluster-scoped Parameter Store store. | `string` | `"ravion-aws-parameter-store"` | no |
| eso_helm_values | Extra YAML docs merged into the external-secrets chart values. | `list(string)` | `[]` | no |
| ebs_csi_driver_enabled | Install the aws-ebs-csi-driver add-on + Pod Identity role. | `bool` | `false` | no |
| ebs_csi_addon_version / ebs_csi_addon_configuration_values | EBS CSI pin / JSON overrides. | `string` | `null` | no |
| cloudwatch_observability_enabled | Install amazon-cloudwatch-observability (Container Insights) + Pod Identity role. | `bool` | `true` | no |
| cloudwatch_observability_addon_version / cloudwatch_observability_addon_configuration_values | CloudWatch Observability pin / JSON overrides. | `string` | `null` | no |
| beacon_enabled | Enroll the cluster and install the Ravion Beacon agent. | `bool` | `false` | no |
| beacon_api_url | Base URL of the Ravion API serving the internal enrollment endpoints, no trailing slash (same value as the runner's `RVN_API_URL`). | `string` | `null` | when `beacon_enabled` |
| beacon_api_token | Runner JWT bearer token for the enrollment call. The organization comes from its claims, never from the request body. Never written to state or outputs. | `string` (sensitive) | `null` | when `beacon_enabled` |
| beacon_endpoint | WebSocket endpoint the agent dials — the single destination an egress policy must allow. | `string` | `"wss://websockets.ravion.com/beacon/v1/connect"` | no |
| beacon_chart_source | `oci://` reference, or a filesystem path to a chart directory for local testing. | `string` | `"oci://public.ecr.aws/ravion/beacon"` | no |
| beacon_chart_version | Beacon **chart** version (not the agent version). Null resolves the latest; ignored for a filesystem chart. | `string` | `null` | no |
| beacon_namespace | Namespace for the agent and its credential Secret (created if missing). | `string` | `"ravion-beacon"` | no |
| beacon_namespace_scope | Namespaces the agent may observe. Empty is cluster-wide; non-empty renders namespaced Roles and no observation ClusterRole at all. | `list(string)` | `[]` | no |
| beacon_deploy_enabled | Let Beacon perform Ravion's Helm deploys from inside the cluster. The widest grant the chart can create. | `bool` | `false` | no |
| beacon_deploy_namespaces | Namespaces Beacon may deploy into. Falls back to `beacon_namespace_scope`; both empty with deploy on fails the apply. | `list(string)` | `[]` | no |
| beacon_exec_enabled | Grant `create` on `pods/exec` — the only way Beacon can run a command inside a container. | `bool` | `false` | no |
| beacon_self_update_enabled | Let the control plane roll the agent forward by patching its own Deployment. | `bool` | `true` | no |
| beacon_image_tag | Agent image tag floor. Not a pin: subsequent changes are ignored (see above). Null uses the chart's `appVersion`. | `string` | `null` | no |
| beacon_helm_values | Extra YAML docs merged into the Beacon chart values (`portForward`, `helmInventory`, `redaction`, `image.repository`, …). | `list(string)` | `[]` | no |
| beacon_project_id / beacon_environment_id / beacon_aws_account_id | Ravion record ids recorded on the agent at enrollment. Optional. | `string` | `null` | no |
| public_subnet_ids | Public subnets for internet-facing load balancers. Required when the public ALB or public NLB is enabled. | `list(string)` | `[]` | no |
| load_balancer_deletion_protection_enabled | Deletion protection on the shared load balancers. | `bool` | `false` | no |
| public_alb_enabled / private_alb_enabled | Create a shared public / private ALB. | `bool` | `false` | no |
| public_alb_https_enabled / private_alb_https_enabled | HTTPS listener (with HTTP→HTTPS redirect). | `bool` | `false` | no |
| public_alb_certificate_arns / private_alb_certificate_arns | ACM certificates for the HTTPS listener (first is default, rest SNI). | `list(string)` | `[]` | no |
| public_alb_ssl_policy / private_alb_ssl_policy | HTTPS listener SSL policy. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| public_alb_idle_timeout / private_alb_idle_timeout | ALB idle timeout in seconds. | `number` | `60` | no |
| public_alb_ingress_cidr_blocks | IPv4 CIDRs allowed to reach the public ALB. | `list(string)` | `["0.0.0.0/0"]` | no |
| private_alb_ingress_cidr_blocks | IPv4 CIDRs allowed to reach the private ALB. | `list(string)` | RFC1918 ranges | no |
| public_alb_ingress_ipv6_cidr_blocks / private_alb_ingress_ipv6_cidr_blocks | IPv6 ingress CIDRs. | `list(string)` | `["::/0"]` / `[]` | no |
| public_alb_ingress_security_group_ids / private_alb_ingress_security_group_ids | Source security groups allowed to reach the ALB. | `list(string)` | `[]` | no |
| public_alb_web_acl_arn | WAFv2 Web ACL for the public ALB. | `string` | `null` | no |
| *_alb_access_logs_enabled / *_alb_access_logs_bucket_arn | ALB access logging toggle and existing bucket. | `bool` / `string` | `false` / `null` | no |
| public_nlb_enabled / private_nlb_enabled | Create a shared public / private NLB. | `bool` | `false` | no |
| *_nlb_cross_zone_load_balancing_enabled | NLB cross-zone load balancing. | `bool` | `false` | no |
| *_nlb_security_group_ids | Additional security groups on the NLB. | `list(string)` | `[]` | no |
| *_nlb_elastic_ips_enabled / *_nlb_elastic_ip_allocation_ids | Static Elastic IPs for the NLB, one allocation per subnet. | `bool` / `list(string)` | `false` / `[]` | no |
| *_nlb_access_logs_enabled / *_nlb_access_logs_bucket_arn | NLB access logging toggle and existing bucket. | `bool` / `string` | `false` / `null` | no |

## Outputs

All outputs are null when the corresponding add-on is disabled.

| Name | Description |
|------|-------------|
| karpenter_namespace / karpenter_chart_version | Karpenter controller install location and version. |
| karpenter_default_node_pool_release | Helm release name of the default NodePool chart. |
| karpenter_controller_role_arn / karpenter_node_role_arn | Karpenter IAM roles. |
| karpenter_node_instance_profile_name | Instance profile used by the default EC2NodeClass. |
| karpenter_interruption_queue_name | SQS interruption queue name. |
| lb_controller_chart_version / lb_controller_namespace | Load balancer controller install version and location. |
| eso_namespace / eso_chart_version | External Secrets Operator install location and version. |
| eso_role_arn | External Secrets Operator Pod Identity role. |
| eso_secrets_manager_store_name / eso_parameter_store_store_name | `ClusterSecretStore` names workload charts reference. |
| ebs_csi_addon_version / ebs_csi_role_arn | EBS CSI add-on version and Pod Identity role. |
| cloudwatch_observability_addon_version / cloudwatch_observability_role_arn | Container Insights add-on version and Pod Identity role. |
| beacon_namespace / beacon_chart_version | Beacon install location and **chart** version (not the running agent version — the control plane owns that). |
| beacon_agent_id | Ravion agent record id (`bagt_…`). Required to rotate or revoke the credential. |
| beacon_client_id | WorkOS Connect client id the agent authenticates as. Not a secret: it is the `sub` claim of every token minted for it. |
| beacon_credential_secret_arn | Secrets Manager secret holding the credential document — the only durable copy of the client secret. |
| public_alb_arn / dns_name / zone_id / arn_suffix / security_group_id / http_listener_arn / https_listener_arn | Shared public ALB attributes for workload target groups, DNS records, and metrics. |
| private_alb_arn / dns_name / zone_id / arn_suffix / security_group_id / http_listener_arn / https_listener_arn | Shared private ALB attributes. |
| public_nlb_arn / dns_name / zone_id / arn_suffix / security_group_id | Shared public NLB attributes. |
| private_nlb_arn / dns_name / zone_id / arn_suffix / security_group_id | Shared private NLB attributes. |

## Notes

- Karpenter CRDs are managed by the dedicated `karpenter-crd` chart because Helm does not upgrade CRDs bundled inside a chart's `crds/` directory. Both charts are pinned to the same version.
- The default NodePool and EC2NodeClass are delivered as a local chart (`charts/karpenter-resources`) because the Helm provider is the only Kubernetes access this stack has.
- On destroy, the Helm releases are removed before the AWS-side resources, so Karpenter drains and terminates the nodes it launched while its IAM roles and queue still exist.
- The cluster must have the Pod Identity Agent add-on (the `compute/eks` composite installs it by default); Karpenter's node access entry additionally requires `authentication_mode = API`.
- The load balancer controller's IAM role and Pod Identity association come from the `compute/eks` composite (`lb_controller_pod_identity_enabled`, on by default); this stack only installs the chart, with `region` and `vpcId` set explicitly so it works under restricted IMDS and on Fargate.
- For automatic subnet discovery, tag public subnets with `kubernetes.io/role/elb = 1` and private subnets with `kubernetes.io/role/internal-elb = 1`, or specify subnets per Ingress via the `alb.ingress.kubernetes.io/subnets` annotation.
- Unlike Karpenter, the `external-secrets` chart renders its CRDs as ordinary templates (`installCRDs`, default on), so Helm upgrades them and no separate CRD chart is needed. The `ClusterSecretStore`s are a separate local chart (`charts/external-secrets-resources`) that `depends_on` the operator release, because CRD-kind objects cannot be applied before the operator's CRDs exist and its validating webhook is serving.
- The External Secrets Operator's `ClusterSecretStore`s carry no `auth` block. The operator resolves credentials through the AWS SDK default credential chain, which the Pod Identity Agent populates from the association this stack creates — so no static AWS credentials exist anywhere in the cluster, and `serviceAccountRef`-style IRSA config is deliberately absent (it conflicts with Pod Identity).
- Beacon's credential `Secret` is a separate local chart (`charts/beacon-credential`) rather than a `kubernetes_secret` resource, for the same reason as the `ClusterSecretStore`s: the Helm provider is the only Kubernetes access this stack has. The credential reaches it through `values` wrapped in `sensitive()`, not through `set_sensitive` — Helm's `--set` parser splits on `,`, `.` and `=`, which silently truncates a client secret containing any of them.
- The beacon chart deliberately creates no credential `Secret` of its own, and grants Beacon **no RBAC on Secrets at all**. The kubelet reads that object and projects it into the container as a read-only volume, which is what keeps the base ClusterRole free of Secret access.
- `beacon_enabled = false` removes the installation but does **not** revoke the agent's WorkOS identity. Revoke through the API first if the cluster is going away; see the rotation table above.
- There is no ordering concern for the Deployment-kind add-ons here (External Secrets Operator, Karpenter, load balancer controller): this stack deploys against a cluster whose system node group already exists, which is what the `compute/eks` composite's cluster → system node group → Deployment-kind add-on chain guarantees.
