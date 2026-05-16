################################################################################
# Application Load Balancer
################################################################################

output "alb_id" {
  description = "The ID of the Application Load Balancer."
  value       = aws_lb.this.id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB for use with CloudWatch Metrics."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (for Route53 alias records)."
  value       = aws_lb.this.zone_id
}

################################################################################
# Listeners
################################################################################

output "http_listener_arn" {
  description = "The ARN of the HTTP listener (null if disabled)."
  value       = local.create_http_listener ? aws_lb_listener.http[0].arn : null
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener (null if disabled)."
  value       = local.create_https_listener ? aws_lb_listener.https[0].arn : null
}

################################################################################
# Security Group
################################################################################

output "security_group_id" {
  description = "The ID of the ALB security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the ALB security group."
  value       = module.security_group.security_group_arn
}

################################################################################
# Access Logs
################################################################################

output "access_logs_bucket_name" {
  description = "The name of the S3 bucket for access logs (null if access logs disabled or using existing bucket)."
  value       = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : null
}

output "access_logs_bucket_arn" {
  description = "The ARN of the S3 bucket for access logs (null if access logs disabled or using existing bucket)."
  value       = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].arn : null
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}

################################################################################
# Ravion-managed domains (null when use_ravion_managed_domains = false)
################################################################################

output "ravion_managed_domains_enabled" {
  description = "Whether the listener's default cert + auto-domain are managed by Ravion."
  value       = var.use_ravion_managed_domains
}

output "ravion_default_url" {
  description = "Auto-provisioned https URL backed by the cluster wildcard cert. Null when Ravion-managed domains are off."
  value       = var.use_ravion_managed_domains && length(domains_alb_attachment.this) > 0 ? domains_alb_attachment.this[0].default_url : null
}

output "ravion_default_fqdn" {
  description = "Auto-provisioned FQDN (bare, no scheme). Null when Ravion-managed domains are off."
  value       = var.use_ravion_managed_domains && length(domains_alb_attachment.this) > 0 ? domains_alb_attachment.this[0].default_fqdn : null
}

output "ravion_default_cert_arn" {
  description = "ARN of the Ravion-issued cluster wildcard cert wired as the listener default. Null when Ravion-managed domains are off."
  value       = var.use_ravion_managed_domains && length(domains_alb_attachment.this) > 0 ? domains_alb_attachment.this[0].default_cert_arn : null
}

output "ravion_alb_attachment_id" {
  description = "Opaque id of the alb_attachment resource — pass downstream callers that need to bind per-service certs to this ALB."
  value       = var.use_ravion_managed_domains && length(domains_alb_attachment.this) > 0 ? domains_alb_attachment.this[0].id : null
}

output "ravion_default_app_domain_id" {
  description = "Opaque id of the auto-allocated app_domain inside this ALB's alb_attachment. Pass to `domains_app_domain.parent_id` on a child allocation so the cluster wildcard cert covers it without per-service ACM work."
  value       = var.use_ravion_managed_domains && length(domains_alb_attachment.this) > 0 ? domains_alb_attachment.this[0].app_domain_id : null
}
