################################################################################
# AWS Load Balancer Controller
################################################################################

output "lb_controller_chart_version" {
  description = "Installed version of the aws-load-balancer-controller Helm chart (null if disabled)."
  value       = local.lb_controller_install ? helm_release.lb_controller[0].version : null
}

output "lb_controller_namespace" {
  description = "Namespace where the AWS Load Balancer Controller is installed (null if disabled)."
  value       = local.lb_controller_install ? helm_release.lb_controller[0].namespace : null
}

################################################################################
# EBS CSI Driver
################################################################################

output "ebs_csi_addon_version" {
  description = "Resolved version of the aws-ebs-csi-driver EKS add-on (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? aws_eks_addon.ebs_csi[0].addon_version : null
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver Pod Identity role (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? module.ebs_csi_role[0].role_arn : null
}

################################################################################
# CloudWatch Observability
################################################################################

output "cloudwatch_observability_addon_version" {
  description = "Resolved version of the amazon-cloudwatch-observability EKS add-on (null if disabled)."
  value       = var.cloudwatch_observability_enabled ? aws_eks_addon.cloudwatch_observability[0].addon_version : null
}

output "cloudwatch_observability_role_arn" {
  description = "ARN of the CloudWatch Observability add-on Pod Identity role (null if disabled)."
  value       = var.cloudwatch_observability_enabled ? module.cloudwatch_observability_role[0].role_arn : null
}

################################################################################
# External Secrets Operator
################################################################################

output "eso_namespace" {
  description = "Kubernetes namespace where the External Secrets Operator is installed (null if disabled)."
  value       = var.eso_enabled ? helm_release.external_secrets[0].namespace : null
}

output "eso_chart_version" {
  description = "Installed version of the external-secrets Helm chart (null if disabled)."
  value       = var.eso_enabled ? helm_release.external_secrets[0].version : null
}

output "eso_role_arn" {
  description = "ARN of the External Secrets Operator Pod Identity role (null if disabled)."
  value       = var.eso_enabled ? module.external_secrets_role[0].role_arn : null
}

output "eso_secrets_manager_store_name" {
  description = "Name of the cluster-scoped AWS Secrets Manager store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for Secrets Manager secrets (null if disabled)."
  value       = var.eso_enabled && var.eso_cluster_secret_stores_enabled ? var.eso_secrets_manager_store_name : null
}

output "eso_parameter_store_store_name" {
  description = "Name of the cluster-scoped AWS SSM Parameter Store store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for SSM parameters (null if disabled)."
  value       = var.eso_enabled && var.eso_cluster_secret_stores_enabled ? var.eso_parameter_store_store_name : null
}

################################################################################
# Karpenter
################################################################################

output "karpenter_namespace" {
  description = "Kubernetes namespace where the Karpenter controller is installed (null if disabled)."
  value       = var.karpenter_enabled ? helm_release.karpenter[0].namespace : null
}

output "karpenter_chart_version" {
  description = "Installed version of the Karpenter Helm chart (null if disabled)."
  value       = var.karpenter_enabled ? helm_release.karpenter[0].version : null
}

output "karpenter_default_node_pool_release" {
  description = "Helm release name of the default NodePool chart (null if disabled)."
  value       = var.karpenter_enabled && var.karpenter_default_node_pool_enabled ? helm_release.karpenter_default_node_pool[0].name : null
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].controller_role_arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role attached to Karpenter-launched nodes (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_role_arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name used by the default EC2NodeClass (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_instance_profile_name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS interruption queue (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].interruption_queue_name : null
}

################################################################################
# Shared Load Balancers
################################################################################

output "public_alb_arn" {
  description = "ARN of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_arn : null
}

output "public_alb_dns_name" {
  description = "DNS name of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_dns_name : null
}

output "public_alb_zone_id" {
  description = "Route 53 zone ID of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_zone_id : null
}

output "public_alb_arn_suffix" {
  description = "ARN suffix of the shared public ALB, for CloudWatch metrics (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_arn_suffix : null
}

output "public_alb_security_group_id" {
  description = "Security group ID of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].security_group_id : null
}

output "public_alb_http_listener_arn" {
  description = "ARN of the shared public ALB HTTP listener (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].http_listener_arn : null
}

output "public_alb_https_listener_arn" {
  description = "ARN of the shared public ALB HTTPS listener (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].https_listener_arn : null
}

output "private_alb_arn" {
  description = "ARN of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_arn : null
}

output "private_alb_dns_name" {
  description = "DNS name of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_dns_name : null
}

output "private_alb_zone_id" {
  description = "Route 53 zone ID of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_zone_id : null
}

output "private_alb_arn_suffix" {
  description = "ARN suffix of the shared private ALB, for CloudWatch metrics (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_arn_suffix : null
}

output "private_alb_security_group_id" {
  description = "Security group ID of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].security_group_id : null
}

output "private_alb_http_listener_arn" {
  description = "ARN of the shared private ALB HTTP listener (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].http_listener_arn : null
}

output "private_alb_https_listener_arn" {
  description = "ARN of the shared private ALB HTTPS listener (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].https_listener_arn : null
}

output "public_nlb_arn" {
  description = "ARN of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_arn : null
}

output "public_nlb_dns_name" {
  description = "DNS name of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_dns_name : null
}

output "public_nlb_zone_id" {
  description = "Route 53 zone ID of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_zone_id : null
}

output "public_nlb_arn_suffix" {
  description = "ARN suffix of the shared public NLB, for CloudWatch metrics (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_arn_suffix : null
}

output "public_nlb_security_group_id" {
  description = "Security group ID of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].security_group_id : null
}

output "private_nlb_arn" {
  description = "ARN of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_arn : null
}

output "private_nlb_dns_name" {
  description = "DNS name of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_dns_name : null
}

output "private_nlb_zone_id" {
  description = "Route 53 zone ID of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_zone_id : null
}

output "private_nlb_arn_suffix" {
  description = "ARN suffix of the shared private NLB, for CloudWatch metrics (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_arn_suffix : null
}

output "private_nlb_security_group_id" {
  description = "Security group ID of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].security_group_id : null
}
