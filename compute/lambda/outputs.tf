################################################################################
# Lambda Function
################################################################################

output "function_name" {
  description = "The name of the Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "The ARN of the Lambda function."
  value       = aws_lambda_function.this.arn
}

output "function_invoke_arn" {
  description = "The invoke ARN of the Lambda function."
  value       = aws_lambda_function.this.invoke_arn
}

output "function_qualified_arn" {
  description = "The qualified ARN of the Lambda function."
  value       = aws_lambda_function.this.qualified_arn
}

output "function_version" {
  description = "The latest published version of the Lambda function."
  value       = aws_lambda_function.this.version
}

output "function_last_modified" {
  description = "The date this resource was last modified."
  value       = aws_lambda_function.this.last_modified
}

################################################################################
# IAM
################################################################################

output "role_arn" {
  description = "The IAM role ARN used by the Lambda function."
  value       = local.lambda_role_arn
}

################################################################################
# CloudWatch Logs
################################################################################

output "log_group_name" {
  description = "The CloudWatch log group name used by the Lambda function."
  value       = local.log_group_name
}

output "log_group_arn" {
  description = "The CloudWatch log group ARN, or null if not created by this module."
  value       = var.create_log_group ? aws_cloudwatch_log_group.this[0].arn : null
}

################################################################################
# Integrations
################################################################################

output "permission_statement_ids" {
  description = "Map of permission item index to statement ID."
  value = {
    for k, v in aws_lambda_permission.this : k => v.statement_id
  }
}

output "event_source_mapping_ids" {
  description = "Map of event source mapping item index to UUID."
  value = {
    for k, v in aws_lambda_event_source_mapping.this : k => v.uuid
  }
}

output "alias_arns" {
  description = "Map of alias names to alias ARNs."
  value = {
    for alias_name, alias in aws_lambda_alias.this : alias_name => alias.arn
  }
}

output "function_url" {
  description = "Lambda function URL, or null when function_url_enabled is false."
  value       = var.function_url_enabled ? aws_lambda_function_url.this[0].function_url : null
}
