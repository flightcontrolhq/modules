################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# Resolve the load balancer the service is attached to so its DNS name and
# zone ID can be exposed as outputs (e.g. for CloudFront origins or DNS
# records). For ALB attachments the load balancer is derived from the first
# listener rule's listener; for NLB attachments the NLB ARN is provided
# directly.
data "aws_lb_listener" "attached" {
  count = local.enable_load_balancer && !local.enable_nlb_listener ? (length(var.load_balancer_attachment.listener_rules) > 0 ? 1 : 0) : 0

  arn = var.load_balancer_attachment.listener_rules[0].listener_arn
}

data "aws_lb" "attached" {
  count = local.enable_load_balancer ? ((local.enable_nlb_listener || length(var.load_balancer_attachment.listener_rules) > 0) ? 1 : 0) : 0

  arn = local.enable_nlb_listener ? local.primary_nlb_listener.nlb_arn : data.aws_lb_listener.attached[0].load_balancer_arn
}

