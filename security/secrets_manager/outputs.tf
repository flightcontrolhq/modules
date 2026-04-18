################################################################################
# Outputs
################################################################################

output "arn" {
  description = "The ARN of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.this.arn
}

output "id" {
  description = "The ID of the Secrets Manager secret (same as ARN)."
  value       = aws_secretsmanager_secret.this.id
}

output "name" {
  description = "The name of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.this.name
}

output "version_id" {
  description = "The unique identifier of the secret version, or null when no version was created."
  value       = length(aws_secretsmanager_secret_version.this) > 0 ? aws_secretsmanager_secret_version.this[0].version_id : null
}
