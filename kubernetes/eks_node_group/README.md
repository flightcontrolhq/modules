# EKS Node Group

Provisions one EKS managed node group, plus its IAM node role (optional) and a
custom launch template (optional, only when the caller customizes anything
beyond AMI / instance shape).

Instantiate this module once per node group. Use a small on-demand "system"
group for control-plane-adjacent workloads (Karpenter, the LB Controller,
CoreDNS, metrics-server) and let Karpenter handle elasticity for everything
else.

## Usage

```hcl
module "system_nodes" {
  source = "git::https://github.com/flightcontrolhq/modules.git//kubernetes/eks_node_group?ref=v1.0.0"

  cluster_name = module.eks.cluster_name
  name         = "system"

  subnet_ids     = module.vpc.private_subnet_ids
  instance_types = ["t3.large"]
  capacity_type  = "ON_DEMAND"

  min_size     = 2
  desired_size = 2
  max_size     = 4

  labels = { role = "system" }
  taints = [{ key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" }]
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
| cluster_name | Name of the EKS cluster the node group joins. | `string` | n/a | yes |
| name | Node group name (unique within cluster). | `string` | n/a | yes |
| subnet_ids | Subnets to launch nodes in. | `list(string)` | n/a | yes |
| capacity_type | `ON_DEMAND`, `SPOT`, or `CAPACITY_BLOCK`. | `string` | `"ON_DEMAND"` | no |
| instance_types | Allowed instance types. | `list(string)` | `["t3.medium"]` | no |
| ami_type | AMI type managed by EKS. | `string` | `"AL2023_x86_64_STANDARD"` | no |
| kubernetes_version | Pin node version (defaults to cluster). | `string` | `null` | no |
| min_size / desired_size / max_size | Scaling bounds. | `number` | 1/1/3 | no |
| max_unavailable | Max nodes unavailable during update (mutually exclusive with percentage). | `number` | `null` | no |
| max_unavailable_percentage | Max % of nodes unavailable during update. | `number` | `33` | no |
| force_update_version | Ignore PDBs during version updates. | `bool` | `false` | no |
| labels | Kubernetes labels. | `map(string)` | `{}` | no |
| taints | Kubernetes taints. | `list(object)` | `[]` | no |
| disk_size / disk_type / disk_iops / disk_throughput | Root volume tuning (triggers launch template). | `number/string/number/number` | `null` | no |
| ebs_kms_key_arn | Encrypt root volume with this KMS key (triggers launch template). | `string` | `null` | no |
| user_data | Raw additional user data (base64-encoded internally; triggers launch template). | `string` | `null` | no |
| security_group_ids | Extra SGs on node ENIs (triggers launch template). | `list(string)` | `[]` | no |
| enable_detailed_monitoring | Enable EC2 1-minute monitoring. | `bool` | `false` | no |
| metadata_http_tokens | IMDSv2 enforcement. | `string` | `"required"` | no |
| metadata_http_put_response_hop_limit | IMDS hop limit. | `number` | `2` | no |
| node_role_arn | BYO node role. When null, module creates one. | `string` | `null` | no |
| additional_node_role_managed_policy_arns | Extra managed policies on the module-created role. | `list(string)` | `[]` | no |
| additional_node_role_inline_policy_statements | Extra inline statements on the module-created role. | `list(object)` | `[]` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| region | AWS region override. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| node_group_arn / node_group_id / node_group_name | Node group identifiers. |
| node_group_status | EKS-reported status. |
| node_group_resources | Underlying ASG / remote access SG. |
| node_role_arn / node_role_name | IAM role used by nodes. |
| launch_template_id / launch_template_arn / launch_template_latest_version | Launch template (null when EKS-default). |
| aws_account_id / region | Account & region info. |

## Notes

- `desired_size` is honored on create and ignored thereafter via `lifecycle.ignore_changes` so an autoscaler can manage capacity without drifting against terraform state. Use `min_size` / `max_size` to constrain it.
- A launch template is only created when at least one of `disk_size`, `disk_type`, `disk_iops`, `disk_throughput`, `ebs_kms_key_arn`, `user_data`, `security_group_ids`, `enable_detailed_monitoring`, or non-default IMDS settings is supplied. Otherwise EKS uses its internal default template (which we cannot modify directly).
- The default node role attaches `AmazonSSMManagedInstanceCore` so you can `aws ssm start-session` into nodes without managing SSH keys.
