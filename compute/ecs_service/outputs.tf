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
# Target Groups - Rolling Deployment
################################################################################

output "target_group_arn" {
  description = "The ARN of the target group (null if load balancer disabled or blue/green deployment)."
  value       = local.enable_load_balancer && var.deployment_type == "rolling" ? aws_lb_target_group.this[0].arn : null
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the target group for CloudWatch metrics."
  value       = local.enable_load_balancer && var.deployment_type == "rolling" ? aws_lb_target_group.this[0].arn_suffix : null
}

output "target_group_name" {
  description = "The name of the target group."
  value       = local.enable_load_balancer && var.deployment_type == "rolling" ? aws_lb_target_group.this[0].name : null
}

################################################################################
# Target Groups - Blue/Green Deployment
################################################################################

output "blue_target_group_arn" {
  description = "The ARN of the blue target group (null if not blue/green deployment)."
  value       = local.enable_load_balancer && var.deployment_type == "blue_green" ? aws_lb_target_group.tg_1[0].arn : null
}

output "blue_target_group_name" {
  description = "The name of the blue target group."
  value       = local.enable_load_balancer && var.deployment_type == "blue_green" ? aws_lb_target_group.tg_1[0].name : null
}

output "green_target_group_arn" {
  description = "The ARN of the green target group (null if not blue/green deployment)."
  value       = local.enable_load_balancer && var.deployment_type == "blue_green" ? aws_lb_target_group.tg_2[0].arn : null
}

output "green_target_group_name" {
  description = "The name of the green target group."
  value       = local.enable_load_balancer && var.deployment_type == "blue_green" ? aws_lb_target_group.tg_2[0].name : null
}

################################################################################
# Combined Target Group Outputs (for convenience)
################################################################################

output "target_group_arns" {
  description = "Map of all target group ARNs created by this module."
  value = local.enable_load_balancer ? (
    var.deployment_type == "rolling" ? {
      primary = aws_lb_target_group.this[0].arn
      } : {
      blue  = aws_lb_target_group.tg_1[0].arn
      green = aws_lb_target_group.tg_2[0].arn
    }
  ) : {}
}

################################################################################
# NLB Listener
################################################################################

output "nlb_listener_arn" {
  description = "The ARN of the NLB listener created by this module (null if not using NLB)."
  value       = local.enable_nlb_listener ? aws_lb_listener.nlb[0].arn : null
}

################################################################################
# Auto Scaling
################################################################################

output "autoscaling_target_arn" {
  description = "The ARN of the Application Auto Scaling target (null if auto scaling disabled)."
  value       = local.enable_auto_scaling ? aws_appautoscaling_target.this[0].id : null
}

output "autoscaling_policies" {
  description = "Map of auto scaling policy ARNs."
  value = local.enable_auto_scaling ? {
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
# CodeDeploy Integration Outputs
################################################################################

output "codedeploy_config" {
  description = "Configuration values needed for CodeDeploy blue/green deployments."
  value = var.deployment_type == "blue_green" && local.enable_load_balancer ? {
    cluster_name       = split("/", var.cluster_arn)[1]
    service_name       = aws_ecs_service.this.name
    blue_target_group  = aws_lb_target_group.tg_1[0].name
    green_target_group = aws_lb_target_group.tg_2[0].name
    listener_arns      = [for rule in var.load_balancer_attachment.listener_rules : rule.listener_arn]
  } : null
}

################################################################################
# Container Information
################################################################################

output "container_name" {
  description = "The name of the primary container (used for load balancer attachment)."
  value       = local.lb_container_name
}

output "container_port" {
  description = "The port of the primary container (used for load balancer attachment)."
  value       = local.lb_container_port
}


