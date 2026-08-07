# EKS Add-ons

Selectable add-ons for an existing EKS cluster, each toggled independently:

| Add-on | Toggle | Default | What it creates |
|---|---|---|---|
| **Karpenter** | `karpenter_enabled` | `true` | Controller + node IAM roles, Pod Identity association, instance profile, EKS access entry, SQS interruption queue, EventBridge rules (via `modules/eks_karpenter`), plus the `karpenter-crd` and `karpenter` Helm charts and an optional default NodePool |
| **AWS Load Balancer Controller** | automatic with any load balancer, or `lb_controller_enabled` opt-in | `false` | `aws-load-balancer-controller` Helm chart wired to the Pod Identity role created by the `compute/eks` composite; registers workload pods into shared load balancer target groups (`TargetGroupBinding`); Ingress → ALB, LoadBalancer Service → NLB |
| **External Secrets Operator** | `eso_enabled` | `true` | `external-secrets` Helm chart + Pod Identity role scoped to Secrets Manager / Parameter Store reads, plus the cluster-scoped `ravion-aws` and `ravion-aws-parameter-store` `ClusterSecretStore`s |
| **EBS CSI driver** | `ebs_csi_driver_enabled` | `false` | `aws-ebs-csi-driver` EKS add-on + Pod Identity role |
| **Container Insights** | `cloudwatch_observability_enabled` | `true` | `amazon-cloudwatch-observability` EKS add-on + Pod Identity role (CloudWatch agent + Fluent Bit) |
| **Shared load balancers** | `public_alb_enabled`, `private_alb_enabled`, `public_nlb_enabled`, `private_nlb_enabled` | `false` | Terraform-managed ALBs/NLBs (via `networking/alb` and `networking/nlb`) that workloads attach to with the load balancer controller's `TargetGroupBinding` CRD, plus cluster security group ingress rules allowing each load balancer to reach pods |

The [`compute/eks`](..) composite intentionally creates none of these, so clusters only carry what they use. EBS CSI and Container Insights are native EKS add-ons installed purely through the AWS API. Karpenter, the AWS Load Balancer Controller, and the External Secrets Operator additionally install Helm charts, which are the only parts that need Kubernetes API connectivity.

> **Connectivity contract (Helm add-ons only):** the machine running Terraform must be able to reach the cluster's Kubernetes API endpoint. For private-endpoint clusters, run inside the cluster VPC with the composite's Ravion Runner security group (`ravion_runner_security_group_id` output) attached, and have the AWS CLI on PATH for `aws eks get-token`. With `karpenter_enabled`, `eso_enabled`, `lb_controller_enabled`, and all four load balancer toggles off, no cluster connectivity is needed.
>
> **Authentication:** set `ravion_runner_role_arn` to the cluster's Ravion Runner role (`ravion_runner_role_arn` output of `compute/eks`) and `aws eks get-token` assumes it — the cluster module registers that role as an EKS access entry with cluster-admin, so per-run pipeline roles never need their own access entries. When null, the identity running Terraform is used directly and must already have cluster access.

## Usage

```hcl
module "eks_addons" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/eks/addons?ref=main"

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
- There is no ordering concern for the Deployment-kind add-ons here (External Secrets Operator, Karpenter, load balancer controller): this stack deploys against a cluster whose system node group already exists, which is what the `compute/eks` composite's cluster → system node group → Deployment-kind add-on chain guarantees.
