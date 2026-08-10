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
# Process Exit Monitoring
################################################################################

output "process_exit_metric_namespace" {
  description = "The CloudWatch namespace of the unexpected process exit metric."
  value       = local.process_exit_metric_namespace
}

output "process_exit_metric_name" {
  description = "The name of the unexpected process exit metric, dimensioned by ServiceName."
  value       = local.process_exit_metric_name
}

output "process_exit_alarm_arn" {
  description = "The ARN of the unexpected process exit alarm, when enabled."
  value       = var.process_exit_alarm_enabled ? aws_cloudwatch_metric_alarm.process_exit[0].arn : null
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
