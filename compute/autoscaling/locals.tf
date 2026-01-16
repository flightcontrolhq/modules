################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/autoscaling"
  }

  # Merged tags: default tags + user-provided tags
  tags = merge(local.default_tags, var.tags)

  # ASG tags formatted with Name tag and optional ECS managed tag
  asg_tags = merge(
    local.tags,
    {
      Name = var.name
    },
    var.ecs_managed ? {
      AmazonECSManaged = "true"
    } : {}
  )

  ################################################################################
  # Feature Flags
  ################################################################################

  # Whether to create a launch template
  create_launch_template = var.create_launch_template && var.launch_template != null

  # Whether to enable warm pool
  enable_warm_pool = var.warm_pool != null

  # Whether to enable notifications
  enable_notifications = var.notifications != null

  # Whether to enable instance refresh
  enable_instance_refresh = var.instance_refresh != null

  # Whether to use mixed instances policy
  enable_mixed_instances_policy = var.mixed_instances_policy != null

  # Whether to enable instance maintenance policy
  enable_instance_maintenance_policy = var.instance_maintenance_policy != null
}
