locals {
  region = coalesce(var.region, data.aws_region.current.id)

  # Ravion-managed domains gate. When true the cluster allocates a
  # wildcard FQDN + issues a wildcard ACM cert in ravion_domains.tf;
  # service modules under this cluster inherit the wildcard via SNI.
  enable_ravion_domain = (
    var.enable_public_alb &&
    var.public_alb_enable_https &&
    var.public_alb_cert_source == "ravion_managed" &&
    var.ravion_dns_zone_id != null &&
    var.ravion_dns_zone_id != ""
  )

  # The ALB's HTTPS listener takes a single default cert + N SNI extras.
  # Ravion-managed mode puts the wildcard first (default); BYO mode uses
  # the customer's list verbatim. Using the validation resource's output
  # ensures the listener depends on ACM validation completing.
  public_alb_effective_certificate_arns = (
    local.enable_ravion_domain
    ? concat([aws_acm_certificate_validation.cluster[0].certificate_arn], var.public_alb_certificate_arns)
    : var.public_alb_certificate_arns
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


