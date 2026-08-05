# EKS Cluster Components

Installs in-cluster components onto an existing EKS cluster via Helm: the Karpenter controller, its CRDs, and an optional general-purpose default NodePool.

This module is the in-cluster counterpart of the [`compute/eks`](..) composite. The composite provisions everything through the AWS API (including all of Karpenter's AWS-side resources when `karpenter_enabled = true`); this module performs the only step that requires Kubernetes API connectivity. Splitting the two keeps cluster provisioning single-apply and makes chart upgrades small, isolated applies.

> **Connectivity contract:** the machine running Terraform must be able to reach the cluster's Kubernetes API endpoint. For private-endpoint clusters, run inside the cluster VPC with the composite's Ravion Runner security group (`ravion_runner_security_group_id` output) attached, and have the AWS CLI on PATH for `aws eks get-token`.

## Usage

```hcl
module "eks_components" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/eks/components?ref=v1.0.0"

  cluster_name = module.eks.cluster_name
  region       = "us-east-2"

  karpenter_interruption_queue_name    = module.eks.karpenter_interruption_queue_name
  karpenter_node_instance_profile_name = module.eks.karpenter_node_instance_profile_name
  cluster_security_group_id            = module.eks.cluster_security_group_id
  node_subnet_ids                      = module.eks.node_subnet_ids
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |
| helm               | >= 3.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the existing EKS cluster to install components onto. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| tags | Tags applied to EC2 instances launched by the default Karpenter NodePool. | `map(string)` | `{}` | no |
| karpenter_controller_namespace | Namespace for the Karpenter controller. Must match the cluster's Pod Identity association. | `string` | `"kube-system"` | no |
| karpenter_controller_service_account | Service account for the Karpenter controller. Must match the cluster's Pod Identity association. | `string` | `"karpenter"` | no |
| karpenter_chart_version | Karpenter (and karpenter-crd) chart version. | `string` | `"1.14.0"` | no |
| karpenter_interruption_queue_name | SQS interruption queue created by the compute/eks stack. | `string` | n/a | yes |
| karpenter_helm_values | Extra YAML docs merged into the Karpenter chart values. | `list(string)` | `[]` | no |
| karpenter_default_node_pool_enabled | Create the default NodePool + EC2NodeClass. | `bool` | `true` | no |
| karpenter_node_instance_profile_name | Instance profile for Karpenter-launched nodes (compute/eks output). | `string` | n/a | yes |
| node_subnet_ids | Subnets the default NodePool launches nodes into. | `list(string)` | n/a | yes |
| cluster_security_group_id | EKS-managed cluster security group attached to Karpenter nodes. | `string` | n/a | yes |
| karpenter_default_node_pool | Default NodePool settings (capacity types, categories, arch, CPU limit, expiry). | `object` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| karpenter_namespace | Namespace where the Karpenter controller is installed. |
| karpenter_chart_version | Installed version of the Karpenter Helm chart. |
| karpenter_default_node_pool_release | Helm release name of the default NodePool chart (null if disabled). |

## Notes

- CRDs are managed by the dedicated `karpenter-crd` chart because Helm does not upgrade CRDs bundled inside a chart's `crds/` directory. Both charts are pinned to the same version.
- The default NodePool and EC2NodeClass are delivered as a local chart (`charts/karpenter-resources`) because the Helm provider is the only Kubernetes access this stack has.
- The cluster must be created by `compute/eks` with `karpenter_enabled = true`; this module does not create IAM roles, the Pod Identity association, or the interruption queue.
