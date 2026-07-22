# EKS Hosting (composite)

Root-style stack that nests EKS primitives under `modules/` and composes them
into a single hosting unit with enforced provisioning order:

1. **Cluster** (`modules/eks_cluster`) — control plane, OIDC, secrets KMS,
   vpc-cni / kube-proxy / Pod Identity Agent, LB Controller role
2. **System node group** (`modules/eks_node_group`) — required compute so
   Deployment-kind add-ons can schedule
3. **Post-compute add-ons** (`modules/eks_addons`) — CoreDNS and optional
   EBS CSI (deadlock without step 2)
4. **Optional Karpenter / Fargate** (`modules/eks_karpenter`,
   `modules/eks_fargate_profile`) — after add-ons are healthy
5. **Karpenter controller install** (Helm) — when `karpenter_enabled` is on,
   the stack installs the `karpenter-crd` and `karpenter` charts plus a
   default NodePool/EC2NodeClass, so autoscaling works out of the box

Child modules live in `compute/eks/modules/` and are **not** independently
published root stacks — they have no `provider` / `cloud {}` blocks. Callers
should consume this composite only.

## Usage

```hcl
module "eks" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/eks?ref=v1.0.0"

  name   = "platform"
  region = "us-east-1"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version             = "1.31"
  public_endpoint_access_enabled = true

  ebs_csi_driver_enabled = true
  karpenter_enabled      = true

  tags = { Environment = "prod" }
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |
| tls                | >= 4.0    |
| helm               | >= 3.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | EKS cluster name. | `string` | n/a | yes |
| vpc_id | VPC ID for the control plane. | `string` | n/a | yes |
| subnet_ids | Control plane subnets (>=2); default node/Fargate placement. | `list(string)` | n/a | yes |
| node_subnet_ids | Optional node/Fargate subnet override. | `list(string)` | `null` | no |
| region | AWS region for the root provider. | `string` | `null` | no |
| tags | Tags applied to all created resources. | `map(string)` | `{}` | no |
| kubernetes_version | Cluster Kubernetes version (`MAJOR.MINOR`). | `string` | `null` | no |
| public_endpoint_access_enabled | Expose the API server publicly. | `bool` | `false` | no |
| private_endpoint_access_enabled | Expose the API server inside the VPC. | `bool` | `true` | no |
| public_access_cidrs | CIDRs allowed to hit the public endpoint. | `list(string)` | `["0.0.0.0/0"]` | no |
| service_ipv4_cidr | Override the service CIDR. | `string` | `null` | no |
| ip_family | `ipv4` or `ipv6`. | `string` | `"ipv4"` | no |
| additional_cluster_security_group_ingress | Extra cluster-SG ingress (CIDR). | `list(object)` | `[]` | no |
| additional_cluster_security_group_ingress_sg | Extra cluster-SG ingress (SG). | `list(object)` | `[]` | no |
| cluster_creator_admin_permissions_enabled | Auto-grant cluster-admin to the creating principal. | `bool` | `true` | no |
| access_entries | EKS access entries. | `map(object)` | `{}` | no |
| enabled_cluster_log_types | Control plane log types. | `list(string)` | `["api","audit","authenticator"]` | no |
| cluster_log_retention_in_days | Control plane log retention. | `number` | `30` | no |
| secrets_encryption_enabled | Envelope-encrypt Kubernetes secrets. | `bool` | `true` | no |
| secrets_kms_key_arn | Existing secrets KMS key ARN. | `string` | `null` | no |
| vpc_cni_addon_version / kube_proxy_addon_version | Pinned DaemonSet add-on versions. | `string` | `null` | no |
| vpc_cni_addon_configuration_values / kube_proxy_addon_configuration_values | JSON config overrides. | `string` | `null` | no |
| pod_identity_agent_enabled | Install eks-pod-identity-agent. | `bool` | `true` | no |
| pod_identity_agent_addon_version | Pin pod identity agent version. | `string` | `null` | no |
| lb_controller_pod_identity_enabled | Create LB Controller Pod Identity role. | `bool` | `true` | no |
| lb_controller_namespace / lb_controller_service_account | LB Controller SA location. | `string` | `"kube-system"` / `"aws-load-balancer-controller"` | no |
| pod_identity_associations | Extra Pod Identity associations. | `map(object)` | `{}` | no |
| deletion_protection_enabled | Protect the cluster from API deletion. | `bool` | `true` | no |
| system_node_group | System managed node group config (object with optional attrs). | `object` | `{}` (defaults: name=`system`, 2/2/4 ON_DEMAND t3.medium) | no |
| additional_node_groups | Extra node groups keyed by name. | `map(object)` | `{}` | no |
| coredns_addon_version / coredns_addon_configuration_values | CoreDNS pin / JSON overrides. | `string` | `null` | no |
| ebs_csi_driver_enabled | Install aws-ebs-csi-driver + Pod Identity. | `bool` | `false` | no |
| ebs_csi_addon_version / ebs_csi_addon_configuration_values | EBS CSI pin / JSON overrides. | `string` | `null` | no |
| cloudwatch_observability_enabled | Install amazon-cloudwatch-observability (Container Insights) + Pod Identity. | `bool` | `true` | no |
| cloudwatch_observability_addon_version / cloudwatch_observability_addon_configuration_values | CloudWatch Observability pin / JSON overrides. | `string` | `null` | no |
| karpenter_enabled | Provision Karpenter AWS-side resources. | `bool` | `false` | no |
| karpenter_controller_namespace / karpenter_controller_service_account | Karpenter SA location. | `string` | `"kube-system"` / `"karpenter"` | no |
| karpenter_node_role_additional_managed_policy_arns | Extra policies on Karpenter node role. | `list(string)` | `[]` | no |
| karpenter_interruption_queue_name | Override interruption queue name. | `string` | `null` | no |
| karpenter_interruption_queue_message_retention_seconds | Interruption queue retention. | `number` | `300` | no |
| karpenter_chart_enabled | Install the Karpenter controller Helm chart in-stack. | `bool` | `true` | no |
| karpenter_chart_version | Karpenter (and karpenter-crd) chart version. | `string` | `"1.14.0"` | no |
| karpenter_helm_values | Extra YAML docs merged into the Karpenter chart values. | `list(string)` | `[]` | no |
| karpenter_default_node_pool_enabled | Create the default NodePool + EC2NodeClass. | `bool` | `true` | no |
| karpenter_default_node_pool | Default NodePool settings (capacity types, categories, arch, CPU limit, expiry). | `object` | `{}` | no |
| fargate_profiles | Fargate profiles keyed by name (`selectors` required). | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name / cluster_arn | Cluster identifiers. |
| cluster_endpoint | Kubernetes API server URL. |
| cluster_certificate_authority_data | Base64 CA cert for kubeconfig. |
| cluster_version | Kubernetes version. |
| region / aws_account_id | Deployment location. |
| oidc_issuer_url / oidc_provider_arn | IRSA wiring. |
| cluster_security_group_id | EKS-managed cluster security group. |
| secrets_kms_key_arn | Secrets KMS key (null if disabled). |
| lb_controller_role_arn | LB Controller Pod Identity role. |
| ebs_csi_role_arn | EBS CSI Pod Identity role (null if disabled). |
| cloudwatch_observability_role_arn | CloudWatch Observability Pod Identity role (null if disabled). |
| system_node_group_name / system_node_group_arn | System node group identifiers. |
| additional_node_group_names | Map of additional node group key -> name. |
| karpenter_controller_role_arn / karpenter_node_role_arn / karpenter_node_instance_profile_name / karpenter_interruption_queue_name | Karpenter outputs (null when disabled). |
| fargate_profile_names | Map of Fargate profile key -> name. |

## Notes

- Ordering is intentional: CoreDNS and the EBS CSI controller are Deployments and
  hang `DEGRADED` for ~20 minutes when no compute exists. The composite
  `depends_on` chain prevents that deadlock.
- When `karpenter_enabled` is on, the stack installs the Karpenter controller
  via Helm (`karpenter-crd` + `karpenter`, same pinned version) and a default
  NodePool/EC2NodeClass from the local `charts/karpenter-resources` chart. Set
  `karpenter_chart_enabled = false` to manage the controller out-of-band (e.g.
  GitOps) while keeping the AWS-side resources, or
  `karpenter_default_node_pool_enabled = false` to bring your own NodePools.
- The Helm provider authenticates with a token minted per apply via
  `aws eks get-token`, so the runner needs the AWS CLI on PATH and network
  reachability to the cluster API endpoint. No cluster credentials are stored
  in state.
- On destroy, the NodePool release is removed first, which lets Karpenter drain
  and terminate the nodes it launched before the controller itself is
  uninstalled.
- Nested modules under `modules/` are internal implementation details of this
  composite — do not instantiate them as separate root stacks.
