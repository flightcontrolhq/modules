################################################################################
# Auto Scaling Group
################################################################################

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group. Deploys target this group's instances."
  value       = module.autoscaling.autoscaling_group_name
}

output "autoscaling_group_arn" {
  description = "The ARN of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_arn
}

################################################################################
# Deploy Contract
################################################################################

output "ssm_document_name" {
  description = "The name of the SSM deploy document run on each instance by the deploy manager."
  value       = aws_ssm_document.deploy.name
}

output "ssm_document_arn" {
  description = "The ARN of the SSM deploy document."
  value       = aws_ssm_document.deploy.arn
}

################################################################################
# Artifact Stores
################################################################################

output "ecr_repository_arn" {
  description = "The ARN of the service ECR repository, when created."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_arn : null
}

output "ecr_repository_url" {
  description = "The URL of the service ECR repository, when created."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_url : null
}

################################################################################
# Load Balancer
################################################################################

output "target_group_arn" {
  description = "The ARN of the service target group, when a load balancer is attached."
  value       = local.load_balancer_creation_enabled ? aws_lb_target_group.app[0].arn : null
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the service target group for CloudWatch dimensions."
  value       = local.load_balancer_creation_enabled ? aws_lb_target_group.app[0].arn_suffix : null
}

################################################################################
# Networking and IAM
################################################################################

output "security_group_id" {
  description = "The ID of the instance security group."
  value       = module.instance_security_group.security_group_id
}

output "instance_role_arn" {
  description = "The ARN of the instance IAM role."
  value       = aws_iam_role.instance.arn
}

################################################################################
# Logging
################################################################################

output "log_group_name" {
  description = "The name of the CloudWatch log group receiving app logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "log_stream_prefix" {
  description = "Prefix of deployment- and instance-scoped app log streams inside the log group."
  value       = "deployment"
}

################################################################################
# Context
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where resources are created."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where resources are created."
  value       = local.region
}

output "backup_policy_id" {
  description = "The ID of the Amazon Data Lifecycle Manager backup policy, when backups are enabled."
  value       = var.backup_enabled ? aws_dlm_lifecycle_policy.service[0].id : null
}

output "backup_target_tag" {
  description = "The instance tag targeted by the backup policy."
  value       = local.backup_target_tag
}

output "backup_snapshot_filter" {
  description = "Tag filter for finding this service's snapshots in the EC2 console or API."
  value = {
    "tag:RavionBackup" = var.name
  }
}

output "backup_ssm_document_name" {
  description = "The SSM consistency document used by DLM, when scripts are enabled."
  value       = local.backup_scripts_enabled ? aws_ssm_document.backup[0].name : null
}

output "backup_dump_bucket_name" {
  description = "The S3 bucket name used for logical dumps, when the destination is S3."
  value       = var.backup_dump_enabled && var.backup_dump_destination == "s3" ? local.backup_dump_bucket_name : null
}

output "backup_dump_bucket_arn" {
  description = "The S3 bucket ARN used for logical dumps, when the destination is S3."
  value       = var.backup_dump_enabled && var.backup_dump_destination == "s3" ? local.backup_dump_bucket_arn : null
}

output "backup_dump_prefix" {
  description = "The destination prefix containing this service's logical dump manifests and artifacts."
  value       = var.backup_dump_enabled ? local.backup_dump_artifact_prefix : null
}

output "backup_dump_ssm_document_name" {
  description = "The SSM command document used to run or restore logical dumps."
  value       = var.backup_dump_enabled ? aws_ssm_document.backup_dump[0].name : null
}

output "backup_dump_termination_document_name" {
  description = "The SSM Automation document used by the termination-time dump hook."
  value       = local.backup_dump_termination_enabled ? aws_ssm_document.backup_termination[0].name : null
}
