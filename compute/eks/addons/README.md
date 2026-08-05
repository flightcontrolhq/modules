# EKS Add-ons

Selectable add-ons for an existing EKS cluster, each toggled independently:

| Add-on | Toggle | Default | What it creates |
|---|---|---|---|
| **Karpenter** | `karpenter_enabled` | `true` | Controller + node IAM roles, Pod Identity association, instance profile, EKS access entry, SQS interruption queue, EventBridge rules (via `modules/eks_karpenter`), plus the `karpenter-crd` and `karpenter` Helm charts and an optional default NodePool |
| **AWS Load Balancer Controller** | `lb_controller_enabled` | `true` | `aws-load-balancer-controller` Helm chart wired to the Pod Identity role created by the `compute/eks` composite; Ingress → ALB, LoadBalancer Service → NLB |
| **EBS CSI driver** | `ebs_csi_driver_enabled` | `false` | `aws-ebs-csi-driver` EKS add-on + Pod Identity role |
| **Container Insights** | `cloudwatch_observability_enabled` | `true` | `amazon-cloudwatch-observability` EKS add-on + Pod Identity role (CloudWatch agent + Fluent Bit) |

The [`compute/eks`](..) composite intentionally creates none of these, so clusters only carry what they use. EBS CSI and Container Insights are native EKS add-ons installed purely through the AWS API. Karpenter and the AWS Load Balancer Controller additionally install Helm charts, which are the only parts that need Kubernetes API connectivity.

> **Connectivity contract (Helm add-ons only):** the machine running Terraform must be able to reach the cluster's Kubernetes API endpoint. For private-endpoint clusters, run inside the cluster VPC with the composite's Ravion Runner security group (`ravion_runner_security_group_id` output) attached, and have the AWS CLI on PATH for `aws eks get-token`. With `karpenter_enabled` and `lb_controller_enabled` both false, no cluster connectivity is needed.
>
> **Authentication:** set `ravion_runner_role_arn` to the cluster's Ravion Runner role (`ravion_runner_role_arn` output of `compute/eks`) and `aws eks get-token` assumes it — the cluster module registers that role as an EKS access entry with cluster-admin, so per-run pipeline roles never need their own access entries. When null, the identity running Terraform is used directly and must already have cluster access.

## Usage

```hcl
module "eks_addons" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/eks/addons?ref=v1.0.0"

  cluster_name = module.eks.cluster_name
  region       = "us-east-2"

  # Karpenter (default on) needs node placement wiring and cluster access
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_subnet_ids           = module.eks.node_subnet_ids
  ravion_runner_role_arn    = module.eks.ravion_runner_role_arn

  ebs_csi_driver_enabled = true
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
| cluster_name | Name of the existing EKS cluster. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| tags | Tags applied to created resources and Karpenter-launched instances. | `map(string)` | `{}` | no |
| karpenter_enabled | Install Karpenter end to end. | `bool` | `true` | no |
| ravion_runner_role_arn | IAM role assumed by `aws eks get-token` for Kubernetes API authentication. | `string` | `null` | no |
| lb_controller_enabled | Install the AWS Load Balancer Controller Helm chart. | `bool` | `true` | no |
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
| node_subnet_ids | Subnets for the default NodePool. Required when Karpenter + default NodePool are enabled. | `list(string)` | `null` | no |
| cluster_security_group_id | Cluster security group for Karpenter nodes. Required when Karpenter + default NodePool are enabled. | `string` | `null` | no |
| karpenter_default_node_pool | Default NodePool settings (capacity types, categories, arch, CPU limit, expiry). | `object` | `{}` | no |
| ebs_csi_driver_enabled | Install the aws-ebs-csi-driver add-on + Pod Identity role. | `bool` | `false` | no |
| ebs_csi_addon_version / ebs_csi_addon_configuration_values | EBS CSI pin / JSON overrides. | `string` | `null` | no |
| cloudwatch_observability_enabled | Install amazon-cloudwatch-observability (Container Insights) + Pod Identity role. | `bool` | `true` | no |
| cloudwatch_observability_addon_version / cloudwatch_observability_addon_configuration_values | CloudWatch Observability pin / JSON overrides. | `string` | `null` | no |

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
| ebs_csi_addon_version / ebs_csi_role_arn | EBS CSI add-on version and Pod Identity role. |
| cloudwatch_observability_addon_version / cloudwatch_observability_role_arn | Container Insights add-on version and Pod Identity role. |

## Notes

- Karpenter CRDs are managed by the dedicated `karpenter-crd` chart because Helm does not upgrade CRDs bundled inside a chart's `crds/` directory. Both charts are pinned to the same version.
- The default NodePool and EC2NodeClass are delivered as a local chart (`charts/karpenter-resources`) because the Helm provider is the only Kubernetes access this stack has.
- On destroy, the Helm releases are removed before the AWS-side resources, so Karpenter drains and terminates the nodes it launched while its IAM roles and queue still exist.
- The cluster must have the Pod Identity Agent add-on (the `compute/eks` composite installs it by default); Karpenter's node access entry additionally requires `authentication_mode = API`.
- The load balancer controller's IAM role and Pod Identity association come from the `compute/eks` composite (`lb_controller_pod_identity_enabled`, on by default); this stack only installs the chart, with `region` and `vpcId` set explicitly so it works under restricted IMDS and on Fargate.
- For automatic subnet discovery, tag public subnets with `kubernetes.io/role/elb = 1` and private subnets with `kubernetes.io/role/internal-elb = 1`, or specify subnets per Ingress via the `alb.ingress.kubernetes.io/subnets` annotation.
- There is no ordering concern for the Deployment-kind add-ons here: this stack deploys against a cluster whose system node group already exists.
