################################################################################
# ECS Infrastructure Role
#
# Native traffic-shift deployments (blue_green / linear / canary) hand
# the load-balancer wiring to the ECS deployment controller: ECS assumes
# this role to register/deregister targets and rewrite the production /
# test listener rules while it shifts traffic between the production and
# alternate target groups.
#
# Created whenever a load balancer is attached (not just for native
# strategies) so the deploy manager can switch any service to a
# traffic-shift strategy on a per-deployment basis without a Terraform
# apply. Rolling deployments never cause ECS to assume it.
################################################################################

data "aws_iam_policy_document" "ecs_infrastructure_assume" {
  count = local.enable_load_balancer ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_infrastructure" {
  count = local.enable_load_balancer ? 1 : 0

  name_prefix        = "${substr(var.name, 0, min(length(var.name), 26))}-infra-"
  assume_role_policy = data.aws_iam_policy_document.ecs_infrastructure_assume[0].json

  tags = merge(local.tags, {
    Name = "${var.name}-ecs-infrastructure"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure_elb" {
  count = local.enable_load_balancer ? 1 : 0

  role       = aws_iam_role.ecs_infrastructure[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}
