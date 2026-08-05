################################################################################
# AWS Load Balancer Controller
################################################################################

output "lb_controller_chart_version" {
  description = "Installed version of the aws-load-balancer-controller Helm chart (null if disabled)."
  value       = var.lb_controller_enabled ? helm_release.lb_controller[0].version : null
}

output "lb_controller_namespace" {
  description = "Namespace where the AWS Load Balancer Controller is installed (null if disabled)."
  value       = var.lb_controller_enabled ? helm_release.lb_controller[0].namespace : null
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
