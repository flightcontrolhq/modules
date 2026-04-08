################################################################################
# Outputs
################################################################################

output "repository_arn" {
  description = "The ARN of the ECR repository."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "The name of the ECR repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "The URL of the ECR repository (in the form <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository_name>)."
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "The registry ID where the repository was created."
  value       = aws_ecr_repository.this.registry_id
}
