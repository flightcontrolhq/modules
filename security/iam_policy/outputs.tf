output "policy_arn" {
  description = "The ARN of the customer-managed IAM policy."
  value       = aws_iam_policy.this.arn
}

output "policy_id" {
  description = "The ID of the customer-managed IAM policy."
  value       = aws_iam_policy.this.id
}

output "policy_name" {
  description = "The name of the customer-managed IAM policy."
  value       = aws_iam_policy.this.name
}

output "policy_path" {
  description = "The path of the customer-managed IAM policy."
  value       = aws_iam_policy.this.path
}

output "attachment_count" {
  description = "The number of entities attached to the customer-managed IAM policy."
  value       = aws_iam_policy.this.attachment_count
}

output "aws_account_id" {
  description = "The AWS account ID where the IAM policy is created."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region used to configure the provider."
  value       = local.region
}
