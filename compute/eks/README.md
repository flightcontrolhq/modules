# EKS Hosting (composite)

Root-style stack that nests EKS primitives under `modules/` and composes them
into a single hosting unit with enforced provisioning order:

1. **Cluster** (`modules/eks_cluster`) — control plane, OIDC, secrets KMS,
   vpc-cni / kube-proxy / Pod Identity Agent, LB Controller role
2. **System node group** (`modules/eks_node_group`) — required compute so
   Deployment-kind add-ons can schedule
3. **Post-compute add-ons** (`modules/eks_addons`) — CoreDNS
   (deadlock without step 2)
4. **Optional Fargate** (`modules/eks_fargate_profile`) — after add-ons are
   healthy

This stack talks only to the AWS API, so it provisions in a single apply with
no connectivity to the cluster's Kubernetes endpoint. Optional extensions —
Karpenter autoscaling, the AWS Load Balancer Controller, the External Secrets
Operator, the EBS CSI driver, and Container Insights — live in
the separate [`compute/eks/addons`](addons/) stack as selectable add-ons, so
clusters only carry what they use.

Child modules live in `compute/eks/modules/` and are **not** independently
published root stacks — they have no `provider` / `cloud {}` blocks. Callers
should consume this composite only.

## Usage

```hcl
module "eks" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/eks?ref=main"

  name   = "platform"
  region = "us-east-1"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version             = "1.31"
  public_endpoint_access_enabled = true

  tags = { Environment = "prod" }
}
```

> **Pinning a `ref`:** this repository has no `vX.Y.Z` tags. Releases are tagged
> per module definition as `rvn-<definition-type>@<x.y.z>` (for example
> `rvn-aws-network@1.0.1`). Once a release of this stack is cut, pin to
> `?ref=rvn-eks@<x.y.z>`; until then use `?ref=main` or a commit SHA.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |
| tls                | >= 4.0    |

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
| ravion_runner_security_group_creation_enabled | Create a Ravion Runner SG allowed to reach the API endpoint (443). | `bool` | `true` | no |
| ravion_runner_role_creation_enabled | Create an assumable IAM role registered as an EKS access entry with cluster-admin, for runner Kubernetes API access. | `bool` | `true` | no |
| ravion_runner_role_trusted_principal_arns | ArnLike patterns restricting who can assume the Ravion Runner role (empty = same-account principals with sts:AssumeRole). | `list(string)` | `[]` | no |
| pod_identity_associations | Extra Pod Identity associations. | `map(object)` | `{}` | no |
| deletion_protection_enabled | Protect the cluster from API deletion. | `bool` | `true` | no |
| system_node_group | System managed node group config (object with optional attrs). | `object` | `{}` (defaults: name=`system`, 2/2/4 ON_DEMAND t3.medium) | no |
| additional_node_groups | Extra node groups keyed by name. | `map(object)` | `{}` | no |
| coredns_addon_version / coredns_addon_configuration_values | CoreDNS pin / JSON overrides. | `string` | `null` | no |
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
| node_subnet_ids | Subnets used for node placement (consumed by `addons`). |
| ravion_runner_security_group_id | Ravion Runner SG allowed to reach the API endpoint (null if disabled). |
| ravion_runner_role_arn | IAM role runners assume for Kubernetes API access (null if disabled). |
| secrets_kms_key_arn | Secrets KMS key (null if disabled). |
| lb_controller_role_arn | LB Controller Pod Identity role. |
| system_node_group_name / system_node_group_arn | System node group identifiers. |
| additional_node_group_names | Map of additional node group key -> name. |
| fargate_profile_names | Map of Fargate profile key -> name. |

## Notes

- Ordering is intentional: CoreDNS is a Deployment and hangs `DEGRADED` for
  ~20 minutes when no compute exists. The composite `depends_on` chain
  prevents that deadlock.
- This module creates no optional add-ons. Karpenter autoscaling, the External
  Secrets Operator, the EBS CSI driver, and Container Insights are selectable
  toggles on the [`compute/eks/addons`](addons/) stack, deployed against this
  cluster.
- `secrets_encryption_enabled` (default `true`) puts Kubernetes Secrets in etcd
  under KMS envelope encryption, using a dedicated CMK per cluster unless
  `secrets_kms_key_arn` supplies one. That is the at-rest half of the secrets
  story; the reference half — workloads naming Secrets Manager / Parameter
  Store ARNs instead of carrying values — is the External Secrets Operator
  add-on, documented in [`compute/eks/addons`](addons/#secrets-external-secrets-operator).
- Nested modules under `modules/` are internal implementation details of this
  composite — do not instantiate them as separate root stacks.
