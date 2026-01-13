################################################################################
# IAM Role
################################################################################

output "role_arn" {
  description = "The ARN of the IAM role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "The name of the IAM role."
  value       = aws_iam_role.this.name
}

output "role_id" {
  description = "The stable unique ID of the IAM role."
  value       = aws_iam_role.this.id
}

output "role_unique_id" {
  description = "The unique ID assigned by AWS to the IAM role."
  value       = aws_iam_role.this.unique_id
}

output "role_path" {
  description = "The path of the IAM role."
  value       = aws_iam_role.this.path
}

output "role_create_date" {
  description = "The creation timestamp of the IAM role."
  value       = aws_iam_role.this.create_date
}

################################################################################
# Instance Profile
################################################################################

output "instance_profile_arn" {
  description = "The ARN of the IAM instance profile (null if not created)."
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].arn : null
}

output "instance_profile_name" {
  description = "The name of the IAM instance profile (null if not created)."
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].name : null
}

output "instance_profile_id" {
  description = "The ID of the IAM instance profile (null if not created)."
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].id : null
}

output "instance_profile_unique_id" {
  description = "The unique ID assigned by AWS to the IAM instance profile (null if not created)."
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].unique_id : null
}

################################################################################
# Policy Information
################################################################################

output "managed_policy_arns" {
  description = "List of managed policy ARNs attached to the role."
  value       = var.managed_policy_arns
}

output "inline_policy_names" {
  description = "List of inline policy names attached to the role."
  value = concat(
    keys(var.inline_policies),
    local.has_inline_policy_statements ? ["inline-statements"] : []
  )
}
