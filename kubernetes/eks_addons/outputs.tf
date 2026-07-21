################################################################################
# CoreDNS
################################################################################

output "coredns_addon_arn" {
  description = "ARN of the coredns EKS add-on."
  value       = aws_eks_addon.coredns.arn
}

output "coredns_addon_version" {
  description = "Resolved version of the coredns EKS add-on."
  value       = aws_eks_addon.coredns.addon_version
}

################################################################################
# EBS CSI
################################################################################

output "ebs_csi_addon_arn" {
  description = "ARN of the aws-ebs-csi-driver EKS add-on (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? aws_eks_addon.ebs_csi[0].arn : null
}

output "ebs_csi_addon_version" {
  description = "Resolved version of the aws-ebs-csi-driver EKS add-on (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? aws_eks_addon.ebs_csi[0].addon_version : null
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver Pod Identity role (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? module.ebs_csi_role[0].role_arn : null
}

output "ebs_csi_role_name" {
  description = "Name of the EBS CSI driver Pod Identity role (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? module.ebs_csi_role[0].role_name : null
}
