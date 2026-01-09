################################################################################
# NLB with Cross-Zone Load Balancing Fixture
#
# NLB configuration with cross-zone load balancing enabled for Terratest.
# Creates a VPC first, then deploys an internet-facing NLB with TCP listener
# on port 80 and cross-zone load balancing enabled.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

locals {
  common_tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../../../networking/vpc"

  name         = var.name
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 2

  tags = local.common_tags
}

################################################################################
# NLB with Cross-Zone Load Balancing
################################################################################

module "nlb" {
  source = "../../../../networking/nlb"

  name       = var.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Internet-facing NLB
  internal = false

  # Enable cross-zone load balancing
  enable_cross_zone_load_balancing = true

  # Disable deletion protection for test cleanup
  enable_deletion_protection = false

  tags = local.common_tags
}

################################################################################
# Target Group
################################################################################

resource "aws_lb_target_group" "tcp" {
  name        = "${var.name}-tcp"
  port        = 80
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

################################################################################
# TCP Listener
################################################################################

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = module.nlb.nlb_arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp.arn
  }

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "nlb_arn" {
  description = "The ARN of the Network Load Balancer."
  value       = module.nlb.nlb_arn
}

output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer."
  value       = module.nlb.nlb_dns_name
}

output "target_group_arn" {
  description = "The ARN of the TCP target group."
  value       = aws_lb_target_group.tcp.arn
}

output "listener_arn" {
  description = "The ARN of the TCP listener."
  value       = aws_lb_listener.tcp.arn
}
