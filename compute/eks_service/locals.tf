################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks_service"
  }

  tags = merge(local.default_tags, var.tags)

  region = coalesce(var.region, data.aws_region.current.region)

  # ELBv2 target group names are capped at 32 characters and the "-tg" suffix
  # takes 3, mirroring the ECS service module's truncation.
  target_group_name = "${substr(var.name, 0, min(length(var.name), 24))}-tg"

  # The health check speaks the same protocol as the target group unless the
  # caller overrides it, which is what ECS does via primary_health_check_protocol.
  health_check_protocol = coalesce(var.health_check.protocol, var.target_group_protocol)
}
