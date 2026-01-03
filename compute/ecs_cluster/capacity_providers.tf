################################################################################
# EC2 Capacity Provider
################################################################################

resource "aws_ecs_capacity_provider" "ec2" {
  count = local.enable_ec2 ? 1 : 0

  name = local.ec2_capacity_provider_name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs[0].arn
    managed_termination_protection = var.ec2_managed_termination_protection

    managed_scaling {
      status                    = var.ec2_managed_scaling_status
      target_capacity           = var.ec2_managed_scaling_target_capacity
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 10
    }
  }

  tags = local.tags
}


