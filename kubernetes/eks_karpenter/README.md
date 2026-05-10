# EKS Karpenter (IAM + Queue helper)

Provisions everything Karpenter needs on the AWS side so a consumer can
`helm install` the controller without writing IAM by hand:

- A controller IAM role trusted by EKS Pod Identity (`pods.eks.amazonaws.com`),
  with the inline policies from upstream's CloudFormation translated into HCL.
- An EKS Pod Identity association binding that role to the controller's
  service account.
- A node IAM role + instance profile for the EC2 instances Karpenter launches,
  plus an `EC2_LINUX` access entry so kubelets can register against an
  `authentication_mode = API` cluster.
- An SQS interruption queue + EventBridge rules for spot interruption,
  rebalance recommendations, instance state changes, capacity reservation
  interruptions, and AWS Health events.

The Helm install of Karpenter itself is the consumer's job — point the chart
at the outputs from this module:

```
settings.clusterName            = <your cluster>
settings.interruptionQueue      = <output: interruption_queue_name>
serviceAccount.name             = <var.controller_service_account, default "karpenter">
serviceAccount.namespace        = <var.controller_namespace, default "kube-system">
```

And in your `EC2NodeClass`:

```
spec.instanceProfile = <output: node_instance_profile_name>
```

## Prerequisites

- The cluster has `eks-pod-identity-agent` running. The `eks_cluster` module installs it by default; otherwise install it yourself.
- The cluster's `authentication_mode` is `API` (or `API_AND_CONFIG_MAP`). Required for the EC2_LINUX access entry to take effect.

## Usage

```hcl
module "karpenter" {
  source = "git::https://github.com/flightcontrolhq/modules.git//kubernetes/eks_karpenter?ref=v1.0.0"

  cluster_name = module.eks.cluster_name
}
```

## Requirements

| Name               | Version    |
| ------------------ | ---------- |
| opentofu/terraform | >= 1.10.0  |
| aws                | >= 5.0     |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | EKS cluster name (used to scope IAM and tag events). | `string` | n/a | yes |
| controller_namespace | Namespace of the Karpenter controller SA. | `string` | `"kube-system"` | no |
| controller_service_account | Karpenter controller SA name. | `string` | `"karpenter"` | no |
| node_role_additional_managed_policy_arns | Extra managed policies for Karpenter-launched nodes. | `list(string)` | `[]` | no |
| interruption_queue_name | Override the default queue name (`karpenter-<cluster>`). | `string` | `null` | no |
| interruption_queue_message_retention_seconds | SQS retention. AWS-recommended default 300s. | `number` | `300` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| region | AWS region override. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| controller_role_arn / controller_role_name | Karpenter controller IAM role. |
| node_role_arn / node_role_name | IAM role on Karpenter-launched nodes. |
| node_instance_profile_name / node_instance_profile_arn | Instance profile (use in EC2NodeClass). |
| interruption_queue_name / interruption_queue_arn / interruption_queue_url | SQS queue. |
| aws_account_id / region | Account & region info. |

## Notes

- The controller IAM policy mirrors the upstream Karpenter CloudFormation template at `aws/karpenter-provider-aws/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml`. When Karpenter publishes a new policy version, update `controller_policies.tf` accordingly.
- The node role uses `AmazonEC2ContainerRegistryPullOnly` rather than `AmazonEC2ContainerRegistryReadOnly` to match the principle of least privilege the upstream chose. If your nodes need to push images (uncommon), attach an extra policy via `var.node_role_additional_managed_policy_arns`.
- The queue policy denies non-TLS traffic and only accepts `SendMessage` from EventBridge / SQS service principals, matching the upstream pattern.
