################################################################################
# Model Invocation Logging
################################################################################

output "model_invocation_logging_configuration_id" {
  description = "The AWS region that identifies the Bedrock model invocation logging configuration."
  value       = aws_bedrock_model_invocation_logging_configuration.this.region
}

output "model_invocation_log_group_name" {
  description = "Name of the CloudWatch log group that receives Bedrock model invocation logs."
  value       = aws_cloudwatch_log_group.model_invocations.name
}

output "model_invocation_log_group_arn" {
  description = "ARN of the CloudWatch log group that receives Bedrock model invocation logs."
  value       = aws_cloudwatch_log_group.model_invocations.arn
}

output "model_invocation_logging_role_arn" {
  description = "ARN of the IAM role assumed by Bedrock to deliver model invocation logs."
  value       = aws_iam_role.model_invocation_logging.arn
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
