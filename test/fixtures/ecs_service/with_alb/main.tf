################################################################################
# ECS Service with ALB Fixture
#
# An ECS service configuration with ALB integration for Terratest integration
# testing. Creates a VPC, ECS cluster, ALB, and a Fargate service registered
# with the ALB target group.
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

  # Enable NAT Gateway so Fargate tasks in private subnets can pull container images
  enable_nat_gateway            = true
  nat_gateway_high_availability = false

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
# ECS Service with ALB Integration
################################################################################

module "ecs_service" {
  source = "../../../../compute/ecs_service"

  name        = var.name
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids
  cluster_arn = module.ecs_cluster.cluster_arn

  # Fargate configuration
  launch_type = "FARGATE"
  task_cpu    = 256
  task_memory = 512

  # Run 1 task for testing
  desired_count = 1

  # Container port
  container_port = 80

  # Don't wait for steady state to speed up tests
  wait_for_steady_state = false

  # Disable circuit breaker for testing (placeholder container won't be healthy)
  deployment_circuit_breaker = {
    enable   = false
    rollback = false
  }

  # ALB integration - rolling deployment with target group and listener rule
  load_balancer_attachment = {
    enabled = true

    target_group = {
      port        = 80
      protocol    = "HTTP"
      target_type = "ip"

      health_check = {
        enabled             = true
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        matcher             = "200-499" # Allow various status codes for placeholder container
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 3
      }
    }

    # Attach to the ALB's HTTP listener with path-based routing
    listener_rules = [
      {
        listener_arn = module.ecs_cluster.public_alb_http_listener_arn
        priority     = 100

        conditions = [
          {
            type   = "path-pattern"
            values = ["/*"]
          }
        ]
      }
    ]
  }

  # Give load balancer time to register targets
  health_check_grace_period_seconds = 60

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

output "service_name" {
  description = "The name of the ECS service."
  value       = module.ecs_service.service_name
}

output "service_arn" {
  description = "The ARN of the ECS service."
  value       = module.ecs_service.service_arn
}

output "task_definition_arn" {
  description = "The ARN of the task definition."
  value       = module.ecs_service.task_definition_arn
}

output "desired_count" {
  description = "The desired number of tasks."
  value       = 1
}

output "security_group_id" {
  description = "The ID of the ECS service security group."
  value       = module.ecs_service.security_group_id
}

output "alb_arn" {
  description = "The ARN of the ALB."
  value       = module.ecs_cluster.public_alb_arn
}

output "alb_dns_name" {
  description = "The DNS name of the ALB."
  value       = module.ecs_cluster.public_alb_dns_name
}

output "target_group_arn" {
  description = "The ARN of the target group."
  value       = module.ecs_service.target_group_arn
}

output "alb_security_group_id" {
  description = "The ID of the ALB security group."
  value       = module.ecs_cluster.public_alb_security_group_id
}
