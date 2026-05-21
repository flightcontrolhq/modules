locals {
  region = coalesce(var.region, data.aws_region.current.id)

  # Listener cert list: BYO ARNs first (user's choice as default cert),
  # then every cert-group's wildcard cert as SNI extras. When BYO is
  # empty, the first cert-group cert becomes default. Both empty =
  # ALB module errors (HTTPS without a cert is invalid).
  cert_group_arns = [
    for _name, g in module.ravion_cert_groups.parent_groups : g.cert_arn
  ]
  public_alb_effective_certificate_arns = concat(
    var.public_alb_certificate_arns,
    local.cert_group_arns,
  )
}

################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/ecs_cluster"
  }

  tags = merge(local.default_tags, var.tags)

  # Determine if EC2 capacity provider should be created
  enable_ec2 = var.ec2_instance_type != null

  # Cluster name
  cluster_name = var.name

  # EC2 capacity provider name
  ec2_capacity_provider_name = local.enable_ec2 ? "${var.name}-ec2" : null

  # Build capacity provider strategy based on enabled providers
  capacity_provider_strategy = concat(
    var.enable_fargate ? [{
      capacity_provider = "FARGATE"
      weight            = var.fargate_weight
      base              = var.fargate_base
    }] : [],
    var.enable_fargate_spot ? [{
      capacity_provider = "FARGATE_SPOT"
      weight            = var.fargate_spot_weight
      base              = var.fargate_spot_base
    }] : [],
    local.enable_ec2 ? [{
      capacity_provider = aws_ecs_capacity_provider.ec2[0].name
      weight            = var.ec2_weight
      base              = var.ec2_base
    }] : []
  )

  # User data script for ECS EC2 instances
  ecs_user_data = local.enable_ec2 ? base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
    ${var.ec2_user_data}
  EOF
  ) : null

  # Instance types for mixed instances policy
  ec2_instance_types = local.enable_ec2 ? concat(
    [var.ec2_instance_type],
    var.ec2_spot_instance_types
  ) : []
}


