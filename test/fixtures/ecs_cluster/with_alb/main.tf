################################################################################
# ECS Cluster with ALB Fixture
#
# An ECS cluster configuration with public ALB integration for Terratest
# integration testing.
# Creates a VPC first, then deploys an ECS cluster with Fargate enabled
# and an internet-facing Application Load Balancer.
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
# ECS Cluster with ALB
################################################################################

module "ecs_cluster" {
  source = "../../../../compute/ecs_cluster"

  name               = var.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  # Enable Fargate capacity provider
  enable_fargate      = true
  enable_fargate_spot = false

  # Enable public ALB
  enable_public_alb                     = true
  public_alb_enable_https               = false
  public_alb_enable_deletion_protection = false

  # Disable Container Insights to reduce costs for testing
  enable_container_insights = false

  tags = local.common_tags
}

################################################################################
# ALB Target Group for ECS Services
#
# Creates a target group that can be used by ECS services to register tasks.
# This demonstrates the ALB integration with ECS cluster.
################################################################################

resource "aws_lb_target_group" "ecs" {
  name        = "${var.name}-ecs-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
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

output "cluster_arn" {
  description = "The ARN of the ECS cluster."
  value       = module.ecs_cluster.cluster_arn
}

output "cluster_name" {
  description = "The name of the ECS cluster."
  value       = module.ecs_cluster.cluster_name
}

output "alb_arn" {
  description = "The ARN of the public Application Load Balancer."
  value       = module.ecs_cluster.public_alb_arn
}

output "alb_dns_name" {
  description = "The DNS name of the public Application Load Balancer."
  value       = module.ecs_cluster.public_alb_dns_name
}

output "alb_target_group_arn" {
  description = "The ARN of the ALB target group for ECS services."
  value       = aws_lb_target_group.ecs.arn
}

output "alb_security_group_id" {
  description = "The ID of the ALB security group."
  value       = module.ecs_cluster.public_alb_security_group_id
}

output "http_listener_arn" {
  description = "The ARN of the HTTP listener."
  value       = module.ecs_cluster.public_alb_http_listener_arn
}
