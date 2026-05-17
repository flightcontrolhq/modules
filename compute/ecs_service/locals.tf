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

  # Determine deployment controller type
  deployment_controller_type = var.deployment_type == "blue_green" ? "CODE_DEPLOY" : "ECS"

  # The control plane sends load_balancer_attachment as a JSON-encoded string
  # so it can template-substitute listener/ALB ARNs from upstream module
  # outputs. Decode it once here, then merge with defaults so downstream
  # references can rely on the fully-populated shape (the original
  # `optional()` defaults on the variable type no longer apply post-decode).
  load_balancer_attachment_raw = (
    var.load_balancer_attachment_json == null || var.load_balancer_attachment_json == ""
    ? null
    : jsondecode(var.load_balancer_attachment_json)
  )

  load_balancer_attachment = local.load_balancer_attachment_raw == null ? null : {
    enabled        = try(local.load_balancer_attachment_raw.enabled, true)
    container_name = try(local.load_balancer_attachment_raw.container_name, null)
    container_port = try(local.load_balancer_attachment_raw.container_port, null)
    listener_rules = try(local.load_balancer_attachment_raw.listener_rules, [])
    nlb_listener   = try(local.load_balancer_attachment_raw.nlb_listener, null)
    target_group = {
      port                 = local.load_balancer_attachment_raw.target_group.port
      protocol             = try(local.load_balancer_attachment_raw.target_group.protocol, "HTTP")
      target_type          = try(local.load_balancer_attachment_raw.target_group.target_type, "ip")
      deregistration_delay = try(local.load_balancer_attachment_raw.target_group.deregistration_delay, 300)
      slow_start           = try(local.load_balancer_attachment_raw.target_group.slow_start, 0)
      health_check = {
        enabled             = try(local.load_balancer_attachment_raw.target_group.health_check.enabled, true)
        path                = try(local.load_balancer_attachment_raw.target_group.health_check.path, "/")
        port                = try(local.load_balancer_attachment_raw.target_group.health_check.port, "traffic-port")
        protocol            = try(local.load_balancer_attachment_raw.target_group.health_check.protocol, null)
        matcher             = try(local.load_balancer_attachment_raw.target_group.health_check.matcher, "200")
        interval            = try(local.load_balancer_attachment_raw.target_group.health_check.interval, 30)
        timeout             = try(local.load_balancer_attachment_raw.target_group.health_check.timeout, 5)
        healthy_threshold   = try(local.load_balancer_attachment_raw.target_group.health_check.healthy_threshold, 3)
        unhealthy_threshold = try(local.load_balancer_attachment_raw.target_group.health_check.unhealthy_threshold, 3)
      }
      stickiness = try(local.load_balancer_attachment_raw.target_group.stickiness, null)
    }
  }

  # Determine if load balancer is configured
  enable_load_balancer = local.load_balancer_attachment != null && local.load_balancer_attachment.enabled

  # Determine if NLB listener should be created (vs ALB listener rules)
  enable_nlb_listener = local.enable_load_balancer && local.load_balancer_attachment.nlb_listener != null

  # Placeholder container name and port
  placeholder_container_name = "app"
  placeholder_container_port = var.container_port

  # Container name and port for load balancer
  lb_container_name = local.enable_load_balancer ? coalesce(
    local.load_balancer_attachment.container_name,
    local.placeholder_container_name
  ) : local.placeholder_container_name

  lb_container_port = local.enable_load_balancer ? coalesce(
    local.load_balancer_attachment.container_port,
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
  enable_auto_scaling = try(var.auto_scaling.enabled, false)

  # Service discovery settings
  enable_service_discovery = var.service_discovery != null
}

