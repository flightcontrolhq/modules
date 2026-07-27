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
# Guardrails
################################################################################

output "guardrail_ids" {
  description = "Map of guardrail key to guardrail ID."
  value       = { for key, guardrail in aws_bedrock_guardrail.this : key => guardrail.guardrail_id }
}

output "guardrail_arns" {
  description = "Map of guardrail key to guardrail ARN."
  value       = { for key, guardrail in aws_bedrock_guardrail.this : key => guardrail.guardrail_arn }
}

output "guardrail_versions" {
  description = "Map of guardrail key to the draft version reported by the guardrail resource."
  value       = { for key, guardrail in aws_bedrock_guardrail.this : key => guardrail.version }
}

output "guardrail_published_versions" {
  description = "Map of guardrail key to the published immutable version number, for guardrails with version creation enabled."
  value       = { for key, version in aws_bedrock_guardrail_version.this : key => version.version }
}

################################################################################
# Custom Models
################################################################################

output "custom_model_arns" {
  description = "Map of custom model key to custom model ARN."
  value       = { for key, model in aws_bedrock_custom_model.this : key => model.custom_model_arn }
}

output "custom_model_job_arns" {
  description = "Map of custom model key to the model customization job ARN."
  value       = { for key, model in aws_bedrock_custom_model.this : key => model.job_arn }
}

output "custom_model_names" {
  description = "Map of custom model key to custom model name."
  value       = { for key, model in aws_bedrock_custom_model.this : key => model.custom_model_name }
}

################################################################################
# Application Inference Profiles
################################################################################

output "inference_profile_ids" {
  description = "Map of inference profile key to inference profile ID."
  value       = { for key, profile in aws_bedrock_inference_profile.this : key => profile.id }
}

output "inference_profile_arns" {
  description = "Map of inference profile key to inference profile ARN."
  value       = { for key, profile in aws_bedrock_inference_profile.this : key => profile.arn }
}

################################################################################
# Provisioned Model Throughput
################################################################################

output "provisioned_model_throughput_arns" {
  description = "Map of provisioned model throughput key to provisioned model ARN."
  value       = { for key, throughput in aws_bedrock_provisioned_model_throughput.this : key => throughput.provisioned_model_arn }
}

################################################################################
# Model Access
################################################################################

output "foundation_model_agreement_model_ids" {
  description = "Map of foundation model agreement key to the model ID the account has accepted access for."
  value       = { for key, agreement in aws_bedrock_foundation_model_agreement.this : key => agreement.model_id }
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
