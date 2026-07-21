# EKS Add-ons

Installs **Deployment-kind** EKS add-ons whose pods require schedulable compute:

- `coredns` (always)
- `aws-ebs-csi-driver` (optional) with its Pod Identity role and association

DaemonSet-kind add-ons (`vpc-cni`, `kube-proxy`, `eks-pod-identity-agent`)
remain in `kubernetes/eks_cluster`.

> **Ordering contract (required):** Apply this module **only after** at least one
> node group or Fargate profile exists on the cluster. CoreDNS and the EBS CSI
> controller are Deployments — without schedulable compute their pods never
> start, the add-ons stay `DEGRADED`, and the apply times out (~20 minutes)
> waiting for `ACTIVE`.

## Usage

```hcl
module "eks" {
  source = "git::https://github.com/flightcontrolhq/modules.git//kubernetes/eks_cluster?ref=v2.0.0"

  name               = "platform"
  kubernetes_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
}

module "node_group" {
  source = "git::https://github.com/flightcontrolhq/modules.git//kubernetes/eks_node_group?ref=v1.0.0"

  cluster_name = module.eks.cluster_name
  name         = "system"

  subnet_ids     = module.vpc.private_subnet_ids
  instance_types = ["t3.large"]

  min_size     = 2
  desired_size = 2
  max_size     = 4
}

# Apply AFTER compute exists — Deployment-kind add-ons need schedulable nodes.
module "eks_addons" {
  source = "git::https://github.com/flightcontrolhq/modules.git//kubernetes/eks_addons?ref=v1.0.0"

  cluster_name           = module.eks.cluster_name
  ebs_csi_driver_enabled = true

  depends_on = [module.node_group]

  tags = { Environment = "prod" }
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the EKS cluster to install add-ons on. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
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

- The EBS CSI driver uses Pod Identity (`ebs-csi-controller-sa` in `kube-system`), not IRSA. The cluster must have the `eks-pod-identity-agent` add-on (enabled by default in `kubernetes/eks_cluster`).
- AmazonEBSCSIDriverPolicy is the AWS-managed policy attached to the EBS CSI Pod Identity role.
