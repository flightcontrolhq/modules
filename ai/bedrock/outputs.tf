################################################################################
# Model Invocation Logging
################################################################################

output "model_invocation_logging_configuration_id" {
  description = "The AWS region that identifies the Bedrock model invocation logging configuration (null if disabled)."
  value       = var.model_invocation_logging_enabled ? aws_bedrock_model_invocation_logging_configuration.this[0].region : null
}

output "model_invocation_log_group_name" {
  description = "Name of the CloudWatch log group that receives Bedrock model invocation logs (null if disabled)."
  value       = var.model_invocation_logging_enabled ? aws_cloudwatch_log_group.model_invocations[0].name : null
}

output "model_invocation_log_group_arn" {
  description = "ARN of the CloudWatch log group that receives Bedrock model invocation logs (null if disabled)."
  value       = var.model_invocation_logging_enabled ? aws_cloudwatch_log_group.model_invocations[0].arn : null
}

output "model_invocation_logging_role_arn" {
  description = "ARN of the IAM role assumed by Bedrock to deliver model invocation logs (null if disabled)."
  value       = var.model_invocation_logging_enabled ? aws_iam_role.model_invocation_logging[0].arn : null
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where Amazon Bedrock is configured."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where Amazon Bedrock is configured."
  value       = local.region
}
