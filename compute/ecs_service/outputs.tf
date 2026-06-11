################################################################################
# ECS Service
################################################################################

output "service_id" {
  description = "The ID of the ECS service."
  value       = aws_ecs_service.this.id
}

output "service_arn" {
  description = "The ARN of the ECS service."
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "The name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "service_cluster" {
  description = "The cluster ARN where the service is running."
  value       = aws_ecs_service.this.cluster
}

output "cluster_name" {
  description = "The name of the ECS cluster where the service is running."
  value       = split("/", var.cluster_arn)[1]
}

################################################################################
# Task Definition
################################################################################

output "task_definition_arn" {
  description = "The ARN of the task definition."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "The family of the task definition."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_revision" {
  description = "The revision of the task definition."
  value       = aws_ecs_task_definition.this.revision
}

################################################################################
# IAM Roles
################################################################################

output "execution_role_arn" {
  description = "The ARN of the task execution role."
  value       = local.create_execution_role ? aws_iam_role.execution[0].arn : var.execution_role_arn
}

output "execution_role_name" {
  description = "The name of the task execution role (null if using external role)."
  value       = local.create_execution_role ? aws_iam_role.execution[0].name : null
}

output "task_role_arn" {
  description = "The ARN of the task role."
  value       = local.create_task_role ? aws_iam_role.task[0].arn : var.task_role_arn
}

output "task_role_name" {
  description = "The name of the task role (null if using external role)."
  value       = local.create_task_role ? aws_iam_role.task[0].name : null
}

################################################################################
# Security Group
################################################################################

output "security_group_id" {
  description = "The ID of the ECS service security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the ECS service security group."
  value       = module.security_group.security_group_arn
}

################################################################################
# Target Groups
#
# A production (tg-1) + alternate (tg-2) pair always exists when a load
# balancer is attached, so the deployment strategy can change per
# deployment without Terraform changes. Rolling deployments only ever
# use the production target group.
################################################################################

output "target_group_arn" {
  description = "The ARN of the production target group the service serves from (alias of production_target_group_arn; null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn : null
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the production target group for CloudWatch metrics."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn_suffix : null
}

output "target_group_name" {
  description = "The name of the production target group the service serves from (alias of production_target_group_name; null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].name : null
}

output "production_target_group_arn" {
  description = "The ARN of the production target group (null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn : null
}

output "production_target_group_name" {
  description = "The name of the production target group."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].name : null
}

output "alternate_target_group_arn" {
  description = "The ARN of the alternate target group ECS shifts traffic to during native traffic-shift deployments (null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_2[0].arn : null
}

output "alternate_target_group_name" {
  description = "The name of the alternate target group."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_2[0].name : null
}

output "target_group_arns" {
  description = "Map of all target group ARNs created by this module."
  value = local.enable_load_balancer ? {
    production = aws_lb_target_group.tg_1[0].arn
    alternate  = aws_lb_target_group.tg_2[0].arn
  } : {}
}

################################################################################
# ECS Infrastructure Role
################################################################################

output "ecs_infrastructure_role_arn" {
  description = "The ARN of the IAM role ECS assumes to manage load-balancer wiring during native traffic-shift deployments (null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_iam_role.ecs_infrastructure[0].arn : null
}

################################################################################
# Listeners
################################################################################

output "listener_arns" {
  description = "ARNs of the ALB listeners the service is attached to (empty if no load balancer or NLB)."
  value       = local.enable_load_balancer ? [for rule in var.load_balancer_attachment.listener_rules : rule.listener_arn] : []
}

output "nlb_listener_arn" {
  description = "The ARN of the NLB listener created by this module (null if not using NLB)."
  value       = local.enable_nlb_listener ? aws_lb_listener.nlb[0].arn : null
}

output "production_listener_rule_arn" {
  description = "ARN of the production listener rule (ALB) or listener (NLB) the ECS deployment controller rewrites during native traffic-shift deployments. This is the value the deploy manager passes as advanced_configuration.production_listener_rule on UpdateService (null if load balancer disabled)."
  value = local.enable_load_balancer ? (
    local.enable_nlb_listener ? aws_lb_listener.nlb[0].arn : aws_lb_listener_rule.alb["0"].arn
  ) : null
}

output "test_listener_rule_arn" {
  description = "ARN of the test listener rule the ECS deployment controller rewrites during the TEST_TRAFFIC_SHIFT lifecycle stages, routing test traffic to the green revision before the production cutover. The deploy manager passes it as advanced_configuration.test_listener_rule on UpdateService. Null when no test listener rule is configured (the common case)."
  value       = local.test_listener_rule_arn
}

################################################################################
# Auto Scaling
################################################################################

output "autoscaling_target_arn" {
  description = "The ARN of the Application Auto Scaling target (null if auto scaling disabled)."
  value       = local.auto_scaling_enabled ? aws_appautoscaling_target.this[0].id : null
}

output "autoscaling_policies" {
  description = "Map of auto scaling policy ARNs."
  value = local.auto_scaling_enabled ? {
    for name, policy in aws_appautoscaling_policy.target_tracking : name => policy.arn
  } : {}
}

################################################################################
# Service Discovery
################################################################################

output "service_discovery_arn" {
  description = "The ARN of the Cloud Map service (null if service discovery disabled)."
  value       = local.enable_service_discovery ? aws_service_discovery_service.this[0].arn : null
}

output "service_discovery_id" {
  description = "The ID of the Cloud Map service (null if service discovery disabled)."
  value       = local.enable_service_discovery ? aws_service_discovery_service.this[0].id : null
}

################################################################################
# Container Information
################################################################################

output "container_name" {
  description = "The name of the primary container."
  value       = local.lb_container_name
}

output "container_port" {
  description = "The port of the primary container (dummy value of 3000 if load balancer disabled)."
  value       = local.enable_load_balancer ? local.lb_container_port : 3000
}

################################################################################
# CloudWatch Logs
################################################################################

output "log_group_name" {
  description = "The name of the CloudWatch log group used by the task."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "The ARN of the CloudWatch log group used by the task."
  value       = aws_cloudwatch_log_group.this.arn
}

output "log_stream_prefix" {
  description = "The awslogs stream prefix for the primary container."
  value       = local.placeholder_container_name
}

################################################################################
# ECR
################################################################################

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository (null if disabled)."
  value       = var.ecr_enabled ? module.ecr[0].repository_arn : null
}

output "ecr_repository_name" {
  description = "The name of the ECR repository (null if disabled)."
  value       = var.ecr_enabled ? module.ecr[0].repository_name : null
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository (null if disabled)."
  value       = var.ecr_enabled ? module.ecr[0].repository_url : null
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


