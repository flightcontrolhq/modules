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

  # Determine deployment controller type
  deployment_controller_type = var.deployment_type == "blue_green" ? "CODE_DEPLOY" : "ECS"

  # Determine if load balancer is configured
  enable_load_balancer = var.load_balancer_attachment != null && var.load_balancer_attachment.enabled

  # Determine if NLB listener should be created (vs ALB listener rules)
  enable_nlb_listener = local.enable_load_balancer && var.load_balancer_attachment.nlb_listener != null

  # Placeholder container name and port
  placeholder_container_name = "app"
  placeholder_container_port = var.container_port

  # Container name and port for load balancer
  lb_container_name = local.enable_load_balancer ? coalesce(
    var.load_balancer_attachment.container_name,
    local.placeholder_container_name
  ) : null

  lb_container_port = local.enable_load_balancer ? coalesce(
    var.load_balancer_attachment.container_port,
    local.placeholder_container_port
  ) : null

  # Determine if we need to create IAM roles
  create_execution_role = var.execution_role_arn == null
  create_task_role      = var.task_role_arn == null

  # Placeholder container doesn't use secrets
  has_secrets = false

  # Hardcoded placeholder container definition - CodeDeploy will replace with actual application
  container_definitions = jsonencode([
    {
      name      = local.placeholder_container_name
      image     = "public.ecr.aws/docker/library/hello-world:latest"
      essential = true
      cpu       = 0
      memory    = null

      portMappings = [
        {
          containerPort = local.placeholder_container_port
          hostPort      = var.network_mode == "awsvpc" ? local.placeholder_container_port : null
          protocol      = "tcp"
          name          = null
          appProtocol   = null
        }
      ]

      environment            = []
      secrets                = []
      healthCheck            = null
      logConfiguration       = null
      mountPoints            = []
      dependsOn              = []
      command                = null
      entryPoint             = null
      workingDirectory       = null
      readonlyRootFilesystem = false
      privileged             = false
      user                   = null
      ulimits                = []
      linuxParameters        = null
      dockerLabels           = null
    }
  ])

  # Auto scaling settings
  enable_auto_scaling = var.auto_scaling != null && var.auto_scaling.enabled

  # Service discovery settings
  enable_service_discovery = var.service_discovery != null
}

