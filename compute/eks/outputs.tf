################################################################################
# Cluster
################################################################################

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.cluster.cluster_name
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster."
  value       = module.cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "The Kubernetes API server endpoint URL."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the Kubernetes API server. Use this in kubeconfig."
  value       = module.cluster.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster."
  value       = module.cluster.cluster_version
}

output "region" {
  description = "The AWS region where the cluster is deployed."
  value       = module.cluster.region
}

output "aws_account_id" {
  description = "The AWS account ID where the cluster is deployed."
  value       = module.cluster.aws_account_id
}

################################################################################
# Identity / Networking
################################################################################

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (for IRSA trust policies)."
  value       = module.cluster.oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider for IRSA."
  value       = module.cluster.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group."
  value       = module.cluster.cluster_security_group_id
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used for Kubernetes secrets envelope encryption (null if disabled)."
  value       = module.cluster.secrets_kms_key_arn
}

output "lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller Pod Identity role (null if disabled)."
  value       = module.cluster.lb_controller_role_arn
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver Pod Identity role (null if disabled)."
  value       = module.addons.ebs_csi_role_arn
}

################################################################################
# Node Groups
################################################################################

output "system_node_group_name" {
  description = "Name of the system managed node group."
  value       = module.system_node_group.node_group_name
}

output "system_node_group_arn" {
  description = "ARN of the system managed node group."
  value       = module.system_node_group.node_group_arn
}

output "additional_node_group_names" {
  description = "Map of additional node group key -> node group name."
  value       = { for k, m in module.node_groups : k => m.node_group_name }
}

################################################################################
# Karpenter (null when disabled)
################################################################################

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (null when karpenter_enabled is false)."
  value       = var.karpenter_enabled ? module.karpenter[0].controller_role_arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role attached to Karpenter-launched nodes (null when karpenter_enabled is false)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_role_arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name for Karpenter EC2NodeClass (null when karpenter_enabled is false)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_instance_profile_name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS interruption queue (null when karpenter_enabled is false)."
  value       = var.karpenter_enabled ? module.karpenter[0].interruption_queue_name : null
}

################################################################################
# Fargate
################################################################################

output "fargate_profile_names" {
  description = "Map of Fargate profile key -> profile name."
  value       = { for k, m in module.fargate_profiles : k => m.fargate_profile_name }
}
