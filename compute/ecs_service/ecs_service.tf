################################################################################
# ECS Service
################################################################################

resource "aws_ecs_service" "this" {
  name    = var.name
  cluster = var.cluster_arn

  task_definition = aws_ecs_task_definition.this.arn

  desired_count = var.desired_count

  # Launch type or capacity provider strategy
  launch_type = length(var.capacity_provider_strategies) == 0 ? var.launch_type : null

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  # Platform version for Fargate
  platform_version = var.launch_type == "FARGATE" ? var.platform_version : null

  # Network configuration (required for awsvpc network mode)
  dynamic "network_configuration" {
    for_each = var.network_mode == "awsvpc" ? [1] : []
    content {
      subnets          = var.subnet_ids
      security_groups  = concat([aws_security_group.this.id], var.security_group_ids)
      assign_public_ip = var.assign_public_ip
    }
  }

  # Deployment controller
  deployment_controller {
    type = local.deployment_controller_type
  }

  # Deployment circuit breaker (only for ECS deployment controller)
  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_type == "rolling" && var.deployment_circuit_breaker.enable ? [1] : []
    content {
      enable   = var.deployment_circuit_breaker.enable
      rollback = var.deployment_circuit_breaker.rollback
    }
  }

  # Deployment min/max healthy percent
  deployment_minimum_healthy_percent = var.deployment_type == "rolling" ? var.deployment_minimum_healthy_percent : null
  deployment_maximum_percent         = var.deployment_type == "rolling" ? var.deployment_maximum_percent : null

  # Load balancer configuration - Rolling deployment
  dynamic "load_balancer" {
    for_each = local.enable_load_balancer && var.deployment_type == "rolling" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = local.lb_container_name
      container_port   = local.lb_container_port
    }
  }

  # Load balancer configuration - Blue/Green deployment (attach to blue initially)
  dynamic "load_balancer" {
    for_each = local.enable_load_balancer && var.deployment_type == "blue_green" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.tg_1[0].arn
      container_name   = local.lb_container_name
      container_port   = local.lb_container_port
    }
  }

  # Health check grace period
  health_check_grace_period_seconds = local.enable_load_balancer ? var.health_check_grace_period_seconds : null

  # Service discovery
  dynamic "service_registries" {
    for_each = local.enable_service_discovery ? [1] : []
    content {
      registry_arn   = aws_service_discovery_service.this[0].arn
      container_name = local.lb_container_name
      container_port = local.lb_container_port
    }
  }

  # ECS Exec
  enable_execute_command = var.enable_execute_command

  # Force new deployment
  force_new_deployment = var.force_new_deployment

  # Wait for steady state
  wait_for_steady_state = var.wait_for_steady_state

  # Tags
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  propagate_tags          = var.propagate_tags

  tags = merge(local.tags, {
    Name = var.name
  })

  # Dependencies
  depends_on = [
    aws_iam_role_policy_attachment.execution_base,
    aws_lb_listener_rule.alb,
  ]

  # Lifecycle for blue/green deployments
  lifecycle {
    ignore_changes = [
      # Ignore task definition changes for blue/green as CodeDeploy manages this
      # Uncomment if using external deployment tools:
      # task_definition,
      # load_balancer,
    ]
  }
}

