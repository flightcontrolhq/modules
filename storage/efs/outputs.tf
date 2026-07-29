################################################################################
# File System Outputs
################################################################################

output "file_system_id" {
  description = "The ID of the EFS file system."
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "The ARN of the EFS file system."
  value       = aws_efs_file_system.this.arn
}

output "file_system_dns_name" {
  description = "The DNS name of the EFS file system."
  value       = aws_efs_file_system.this.dns_name
}

################################################################################
# Mount Target Outputs
################################################################################

output "mount_target_ids" {
  description = "Map of subnet ID to mount target ID."
  value       = { for subnet_id, mount_target in aws_efs_mount_target.this : subnet_id => mount_target.id }
}

################################################################################
# Access Point Outputs
################################################################################

output "access_point_id" {
  description = "The ID of the EFS access point."
  value       = local.create_access_point ? aws_efs_access_point.this[0].id : null
}

output "access_point_arn" {
  description = "The ARN of the EFS access point."
  value       = local.create_access_point ? aws_efs_access_point.this[0].arn : null
}

################################################################################
# Security Group Outputs
################################################################################

output "security_group_id" {
  description = "The ID of the mount target security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the mount target security group."
  value       = module.security_group.security_group_arn
}

output "client_security_group_id" {
  description = "The ID of the client security group. Attach this security group to workloads that need NFS access to the file system."
  value       = module.client_security_group.security_group_id
}

output "client_security_group_arn" {
  description = "The ARN of the client security group."
  value       = module.client_security_group.security_group_arn
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}
