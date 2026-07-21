# EKS Add-ons

Internal child module of [`compute/eks`](../..) — consumed via the composite only; not independently versioned or published.

Installs **Deployment-kind** EKS add-ons whose pods require schedulable compute:

- `coredns` (always)
- `aws-ebs-csi-driver` (optional) with its Pod Identity role and association

DaemonSet-kind add-ons (`vpc-cni`, `kube-proxy`, `eks-pod-identity-agent`)
remain in `compute/eks/modules/eks_cluster`.

> **Ordering contract (required):** Apply this module **only after** at least one
> node group or Fargate profile exists on the cluster. CoreDNS and the EBS CSI
> controller are Deployments — without schedulable compute their pods never
> start, the add-ons stay `DEGRADED`, and the apply times out (~20 minutes)
> waiting for `ACTIVE`.

## Usage

Prefer the [`compute/eks`](../..) composite. This module is nested under
`compute/eks/modules/` and is not independently published.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the EKS cluster to install add-ons on. | `string` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| coredns_addon_version | Pinned version for the coredns add-on. When null, AWS resolves the most recent compatible version. | `string` | `null` | no |
| coredns_addon_configuration_values | JSON string of add-on configuration overrides for coredns. | `string` | `null` | no |
| ebs_csi_driver_enabled | Install the aws-ebs-csi-driver add-on and create its Pod Identity role. | `bool` | `false` | no |
| ebs_csi_addon_version | Pinned version for the aws-ebs-csi-driver add-on. When null, AWS resolves the most recent compatible version. | `string` | `null` | no |
| ebs_csi_addon_configuration_values | JSON string of add-on configuration overrides for aws-ebs-csi-driver. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| coredns_addon_arn | ARN of the coredns EKS add-on. |
| coredns_addon_version | Resolved version of the coredns EKS add-on. |
| ebs_csi_addon_arn | ARN of the aws-ebs-csi-driver EKS add-on (null if disabled). |
| ebs_csi_addon_version | Resolved version of the aws-ebs-csi-driver EKS add-on (null if disabled). |
| ebs_csi_role_arn | ARN of the EBS CSI driver Pod Identity role (null if disabled). |
| ebs_csi_role_name | Name of the EBS CSI driver Pod Identity role (null if disabled). |

## Notes

- The EBS CSI driver uses Pod Identity (`ebs-csi-controller-sa` in `kube-system`), not IRSA. The cluster must have the `eks-pod-identity-agent` add-on (enabled by default in `compute/eks/modules/eks_cluster`).
- AmazonEBSCSIDriverPolicy is the AWS-managed policy attached to the EBS CSI Pod Identity role.
