################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.tags, {
    Name = local.cluster_name
  })
}

################################################################################
# Cluster Capacity Providers Association
################################################################################

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = concat(
    var.enable_fargate ? ["FARGATE"] : [],
    var.enable_fargate_spot ? ["FARGATE_SPOT"] : [],
    local.enable_ec2 ? [aws_ecs_capacity_provider.ec2[0].name] : []
  )

  dynamic "default_capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}

