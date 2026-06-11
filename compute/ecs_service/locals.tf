locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/ecs_service"
  }

  tags = merge(local.default_tags, var.tags)

  # Every strategy runs on the native ECS deployment controller — the
  # blue_green / linear / canary traffic shifts are executed by ECS
  # itself (deployment_configuration.strategy), not CodeDeploy.
  deployment_controller_type = "ECS"

  # Strategies that run the ECS controller's traffic-shift state machine
  # over two target groups (production + alternate). Only used to seed
  # deployment_configuration at create time — the target-group pair,
  # infrastructure role, and advanced_configuration are provisioned for
  # every load-balanced service so the strategy can change per
  # deployment without Terraform changes.
  is_native_traffic_shift = contains(["blue_green", "linear", "canary"], var.deployment_type)

  # Map the module's strategy name to the AWS deploymentConfiguration enum.
  deployment_strategy = {
    rolling    = "ROLLING"
    blue_green = "BLUE_GREEN"
    linear     = "LINEAR"
    canary     = "CANARY"
  }[var.deployment_type]

  # Determine if load balancer is configured
  enable_load_balancer = var.load_balancer_attachment != null && var.load_balancer_attachment.enabled

  # Determine if NLB listener should be created (vs ALB listener rules)
  enable_nlb_listener = local.enable_load_balancer && var.load_balancer_attachment.nlb_listener != null

  # Determine if a dedicated test listener rule should be created. Drives
  # the advanced_configuration.test_listener_rule wiring and the
  # TEST_TRAFFIC_SHIFT lifecycle stages on native traffic-shift deploys.
  green_alb_listener_rule_enabled = local.enable_load_balancer && var.load_balancer_attachment.test_listener_rule != null

  # ARN passed to advanced_configuration.test_listener_rule and exported:
  # the module-created rule when configured, else an externally-managed
  # rule ARN supplied by the caller, else null.
  test_listener_rule_arn = local.green_alb_listener_rule_enabled ? aws_lb_listener_rule.test[0].arn : var.test_listener_rule_arn

  # Placeholder container name and port
  placeholder_container_name = "app"
  placeholder_container_port = var.container_port

  # Container name and port for load balancer
  lb_container_name = local.enable_load_balancer ? coalesce(
    var.load_balancer_attachment.container_name,
    local.placeholder_container_name
  ) : local.placeholder_container_name

  lb_container_port = local.enable_load_balancer ? coalesce(
    var.load_balancer_attachment.container_port,
    local.placeholder_container_port
  ) : null

  # Determine if we need to create IAM roles
  create_execution_role = var.execution_role_arn == null
  create_task_role      = var.task_role_arn == null


  # Hardcoded placeholder container definition - the external deployment controller will replace with the actual application
  container_definitions = jsonencode([
    {
      name      = local.placeholder_container_name
      image     = "public.ecr.aws/docker/library/hello-world:latest"
      essential = true
      cpu       = 0
      memory    = null

      stopTimeout = 30

      portMappings = [
        {
          containerPort = local.placeholder_container_port
          hostPort      = var.network_mode == "awsvpc" ? local.placeholder_container_port : null
          protocol      = "tcp"
          name          = null
          appProtocol   = null
        }
      ]

      environment = []
      secrets     = []
      healthCheck = null

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.name}"
          awslogs-region        = local.region
          awslogs-stream-prefix = local.placeholder_container_name
          awslogs-create-group  = "true"
        }
        secretOptions = []
      }

      mountPoints            = []
      volumesFrom            = []
      dependsOn              = []
      command                = null
      entryPoint             = null
      workingDirectory       = null
      readonlyRootFilesystem = false
      privileged             = false
      user                   = null
      ulimits                = []
      systemControls         = []
      linuxParameters = {
        initProcessEnabled = true
        capabilities       = null
        devices            = []
        maxSwap            = null
        sharedMemorySize   = null
        swappiness         = null
        tmpfs              = []
      }
      dockerLabels = null
    }
  ])

  # Auto scaling settings
  auto_scaling_enabled = var.auto_scaling != null && var.auto_scaling.enabled

  # Service discovery settings
  enable_service_discovery = var.service_discovery != null
}

