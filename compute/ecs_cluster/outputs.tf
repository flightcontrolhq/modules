################################################################################
# ECS Cluster
################################################################################

output "cluster_id" {
  description = "The ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "The name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

################################################################################
# Capacity Providers
################################################################################

output "fargate_capacity_provider_name" {
  description = "The name of the Fargate capacity provider (null if disabled)."
  value       = var.enable_fargate ? "FARGATE" : null
}

output "fargate_spot_capacity_provider_name" {
  description = "The name of the Fargate Spot capacity provider (null if disabled)."
  value       = var.enable_fargate_spot ? "FARGATE_SPOT" : null
}

output "ec2_capacity_provider_name" {
  description = "The name of the EC2 capacity provider (null if disabled)."
  value       = local.enable_ec2 ? aws_ecs_capacity_provider.ec2[0].name : null
}

output "ec2_capacity_provider_arn" {
  description = "The ARN of the EC2 capacity provider (null if disabled)."
  value       = local.enable_ec2 ? aws_ecs_capacity_provider.ec2[0].arn : null
}

################################################################################
# EC2 Infrastructure
################################################################################

output "launch_template_id" {
  description = "The ID of the EC2 launch template (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_launch_template.ecs[0].id : null
}

output "launch_template_arn" {
  description = "The ARN of the EC2 launch template (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_launch_template.ecs[0].arn : null
}

output "autoscaling_group_arn" {
  description = "The ARN of the Auto Scaling Group (null if EC2 disabled)."
  value       = local.enable_ec2 ? module.ecs_autoscaling[0].autoscaling_group_arn : null
}

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group (null if EC2 disabled)."
  value       = local.enable_ec2 ? module.ecs_autoscaling[0].autoscaling_group_name : null
}

output "ecs_instance_role_arn" {
  description = "The ARN of the IAM role for ECS EC2 instances (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_iam_role.ecs_instance[0].arn : null
}

output "ecs_instance_role_name" {
  description = "The name of the IAM role for ECS EC2 instances (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_iam_role.ecs_instance[0].name : null
}

output "ecs_instance_security_group_id" {
  description = "The ID of the security group for ECS EC2 instances (null if EC2 disabled)."
  value       = local.enable_ec2 ? module.ecs_instance_security_group[0].security_group_id : null
}

################################################################################
# Public ALB
################################################################################

output "public_alb_arn" {
  description = "The ARN of the public ALB (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].alb_arn : null
}

output "public_alb_id" {
  description = "The ID of the public ALB (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].alb_id : null
}

output "public_alb_dns_name" {
  description = "The DNS name of the public ALB (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].alb_dns_name : null
}

output "public_alb_zone_id" {
  description = "The canonical hosted zone ID of the public ALB (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].alb_zone_id : null
}

output "public_alb_arn_suffix" {
  description = "The ARN suffix of the public ALB for CloudWatch Metrics (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].alb_arn_suffix : null
}

output "public_alb_security_group_id" {
  description = "The ID of the public ALB security group (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].security_group_id : null
}

output "public_alb_http_listener_arn" {
  description = "The ARN of the public ALB HTTP listener (null if disabled)."
  value       = var.enable_public_alb ? module.public_alb[0].http_listener_arn : null
}

output "public_alb_https_listener_arn" {
  description = "The ARN of the public ALB HTTPS listener (null if HTTPS disabled)."
  value       = var.enable_public_alb && (var.public_alb_enable_https || var.use_ravion_managed_domains) ? module.public_alb[0].https_listener_arn : null
}

################################################################################
# Private ALB
################################################################################

output "private_alb_arn" {
  description = "The ARN of the private ALB (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].alb_arn : null
}

output "private_alb_id" {
  description = "The ID of the private ALB (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].alb_id : null
}

output "private_alb_dns_name" {
  description = "The DNS name of the private ALB (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].alb_dns_name : null
}

output "private_alb_zone_id" {
  description = "The canonical hosted zone ID of the private ALB (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].alb_zone_id : null
}

output "private_alb_arn_suffix" {
  description = "The ARN suffix of the private ALB for CloudWatch Metrics (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].alb_arn_suffix : null
}

output "private_alb_security_group_id" {
  description = "The ID of the private ALB security group (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].security_group_id : null
}

output "private_alb_http_listener_arn" {
  description = "The ARN of the private ALB HTTP listener (null if disabled)."
  value       = var.enable_private_alb ? module.private_alb[0].http_listener_arn : null
}

output "private_alb_https_listener_arn" {
  description = "The ARN of the private ALB HTTPS listener (null if HTTPS disabled)."
  value       = var.enable_private_alb && (var.private_alb_enable_https || var.use_ravion_managed_domains) ? module.private_alb[0].https_listener_arn : null
}

################################################################################
# Public NLB
################################################################################

output "public_nlb_arn" {
  description = "The ARN of the public NLB (null if disabled)."
  value       = var.enable_public_nlb ? module.public_nlb[0].nlb_arn : null
}

output "public_nlb_id" {
  description = "The ID of the public NLB (null if disabled)."
  value       = var.enable_public_nlb ? module.public_nlb[0].nlb_id : null
}

output "public_nlb_dns_name" {
  description = "The DNS name of the public NLB (null if disabled)."
  value       = var.enable_public_nlb ? module.public_nlb[0].nlb_dns_name : null
}

output "public_nlb_zone_id" {
  description = "The canonical hosted zone ID of the public NLB (null if disabled)."
  value       = var.enable_public_nlb ? module.public_nlb[0].nlb_zone_id : null
}

output "public_nlb_arn_suffix" {
  description = "The ARN suffix of the public NLB for CloudWatch Metrics (null if disabled)."
  value       = var.enable_public_nlb ? module.public_nlb[0].nlb_arn_suffix : null
}

################################################################################
# Private NLB
################################################################################

output "private_nlb_arn" {
  description = "The ARN of the private NLB (null if disabled)."
  value       = var.enable_private_nlb ? module.private_nlb[0].nlb_arn : null
}

output "private_nlb_id" {
  description = "The ID of the private NLB (null if disabled)."
  value       = var.enable_private_nlb ? module.private_nlb[0].nlb_id : null
}

output "private_nlb_dns_name" {
  description = "The DNS name of the private NLB (null if disabled)."
  value       = var.enable_private_nlb ? module.private_nlb[0].nlb_dns_name : null
}

output "private_nlb_zone_id" {
  description = "The canonical hosted zone ID of the private NLB (null if disabled)."
  value       = var.enable_private_nlb ? module.private_nlb[0].nlb_zone_id : null
}

output "private_nlb_arn_suffix" {
  description = "The ARN suffix of the private NLB for CloudWatch Metrics (null if disabled)."
  value       = var.enable_private_nlb ? module.private_nlb[0].nlb_arn_suffix : null
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
  description = "Whether the public + private ALBs have Ravion-managed default certs."
  value       = var.use_ravion_managed_domains
}

# Public ALB
output "ravion_public_alb_default_url" {
  description = "Auto-provisioned https URL for the public ALB (null if disabled)."
  value       = var.enable_public_alb ? try(module.public_alb[0].ravion_default_url, null) : null
}

output "ravion_public_alb_default_fqdn" {
  description = "Auto-provisioned FQDN for the public ALB (null if disabled)."
  value       = var.enable_public_alb ? try(module.public_alb[0].ravion_default_fqdn, null) : null
}

output "ravion_public_alb_default_cert_arn" {
  description = "ARN of the Ravion-issued cluster cert wired as the public ALB listener default."
  value       = var.enable_public_alb ? try(module.public_alb[0].ravion_default_cert_arn, null) : null
}

output "ravion_public_alb_default_app_domain_id" {
  description = "App-domain id of the public ALB's auto allocation. Pass to ecs_service `ravion_parent_app_domain_id` so per-service auto-domains live under the cluster's cert."
  value       = var.enable_public_alb ? try(module.public_alb[0].ravion_default_app_domain_id, null) : null
}

# Private ALB
output "ravion_private_alb_default_url" {
  description = "Auto-provisioned https URL for the private ALB (null if disabled)."
  value       = var.enable_private_alb ? try(module.private_alb[0].ravion_default_url, null) : null
}

output "ravion_private_alb_default_fqdn" {
  description = "Auto-provisioned FQDN for the private ALB (null if disabled)."
  value       = var.enable_private_alb ? try(module.private_alb[0].ravion_default_fqdn, null) : null
}

output "ravion_private_alb_default_cert_arn" {
  description = "ARN of the Ravion-issued cluster cert wired as the private ALB listener default."
  value       = var.enable_private_alb ? try(module.private_alb[0].ravion_default_cert_arn, null) : null
}

output "ravion_private_alb_default_app_domain_id" {
  description = "App-domain id of the private ALB's auto allocation. Pass to ecs_service `ravion_parent_app_domain_id` for private-routed services."
  value       = var.enable_private_alb ? try(module.private_alb[0].ravion_default_app_domain_id, null) : null
}
