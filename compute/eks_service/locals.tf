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

  # A listener ARN is what makes this workload web-facing. Worker and cron
  # stacks pass null, and the target group, listener rule, and load balancer
  # lookup all drop out, leaving only the optional ECR repository and Fargate
  # profile. This mirrors compute/ecs_service, where a nullable
  # load_balancer_attachment gates the same objects.
  enable_load_balancer = var.listener_arn != null

  # ELBv2 target group names are capped at 32 characters and the "-tg" suffix
  # takes 3, mirroring the ECS service module's truncation.
  target_group_name = "${substr(var.name, 0, min(length(var.name), 24))}-tg"

  # The health check speaks the same protocol as the target group unless the
  # caller overrides it, which is what ECS does via primary_health_check_protocol.
  health_check_protocol = coalesce(var.target_group_health_check.protocol, var.target_group_protocol)

  # The release teardown needs every piece of the release's identity and the
  # means to reach the cluster; the resource's precondition refuses an apply
  # that enables it without them, rather than a destroy that fails late.
  workload_release_cleanup_enabled = var.workload_release_cleanup_enabled
}
