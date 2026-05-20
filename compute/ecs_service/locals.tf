locals {
  region = coalesce(var.region, data.aws_region.current.id)

  # Either input form (id or given_id) drives the lookup. The data
  # source's count is gated on this string being non-empty.
  dns_provider_lookup_key = coalesce(
    var.ravion_dns_provider_id,
    var.ravion_dns_provider_given_id,
    "",
  )

  # The resolved DnsProvider row (only present when the data source's
  # count == 1). Per-variant attribute groups (`route53_ravion`,
  # `route53`, `cloudflare`, `external`) drive the routing-record
  # write path dispatch in ravion_domains.tf.
  dns_provider = local.dns_provider_lookup_key != "" ? data.ravion_dns_provider.this[0] : null

  # Per-variant flags. Mutually exclusive when set.
  is_route53_ravion = local.dns_provider != null && local.dns_provider.route53_ravion != null
  is_route53        = local.dns_provider != null && local.dns_provider.route53 != null
  is_cloudflare     = local.dns_provider != null && local.dns_provider.cloudflare != null
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

  # Determine if load balancer is configured
  enable_load_balancer = try(var.load_balancer_attachment.enabled, false)

  # Determine if NLB listener should be created (vs ALB listener rules)
  enable_nlb_listener = local.enable_load_balancer && try(var.load_balancer_attachment.nlb_listener, null) != null

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
  enable_auto_scaling = try(var.auto_scaling.enabled, false)

  # Service discovery settings
  enable_service_discovery = var.service_discovery != null
}

