################################################################################
# ECS Service with Auto Scaling Fixture
#
# An ECS service configuration with auto scaling enabled for Terratest integration
# testing. Creates a VPC, ECS cluster, and a Fargate service with auto scaling
# policies configured (min=1, max=3).
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
# ECS Cluster
################################################################################

module "ecs_cluster" {
  source = "../../../../compute/ecs_cluster"

  name               = var.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Enable Fargate capacity provider
  enable_fargate      = true
  enable_fargate_spot = false

  # Disable Container Insights to reduce costs for testing
  enable_container_insights = false

  tags = local.common_tags
}

################################################################################
# ECS Service with Auto Scaling
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

  # Run 1 task for testing (module defaults to 0)
  desired_count = 1

  # Container port (placeholder container definition in module)
  container_port = 80

  # Don't wait for steady state to speed up tests
  # (placeholder container may not be healthy)
  wait_for_steady_state = false

  # Disable circuit breaker for testing (placeholder container won't be healthy)
  deployment_circuit_breaker = {
    enable   = false
    rollback = false
  }

  # Auto scaling configuration
  auto_scaling = {
    enabled      = true
    min_capacity = 1
    max_capacity = 3

    target_tracking = [
      {
        policy_name        = "${var.name}-cpu-scaling"
        target_value       = 70.0
        predefined_metric  = "ECSServiceAverageCPUUtilization"
        scale_in_cooldown  = 60
        scale_out_cooldown = 60
        disable_scale_in   = false
      }
    ]
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

output "autoscaling_target_arn" {
  description = "The ARN of the Application Auto Scaling target."
  value       = module.ecs_service.autoscaling_target_arn
}

output "autoscaling_policies" {
  description = "Map of auto scaling policy ARNs."
  value       = module.ecs_service.autoscaling_policies
}

output "autoscaling_min_capacity" {
  description = "The minimum capacity for auto scaling."
  value       = 1
}

output "autoscaling_max_capacity" {
  description = "The maximum capacity for auto scaling."
  value       = 3
}
