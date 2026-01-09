################################################################################
# ECS Cluster Fargate Spot Fixture
#
# An ECS cluster configuration with both Fargate and Fargate Spot capacity
# providers for Terratest integration testing.
# Creates a VPC first, then deploys an ECS cluster with Fargate and Fargate Spot enabled.
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
# ECS Cluster
################################################################################

module "ecs_cluster" {
  source = "../../../../compute/ecs_cluster"

  name               = var.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Enable both Fargate and Fargate Spot capacity providers
  enable_fargate      = true
  enable_fargate_spot = true

  # Disable Container Insights to reduce costs for testing
  enable_container_insights = false

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

output "capacity_providers" {
  description = "The list of capacity providers attached to the cluster."
  value       = ["FARGATE", "FARGATE_SPOT"]
}

output "fargate_capacity_provider_name" {
  description = "The name of the Fargate capacity provider."
  value       = module.ecs_cluster.fargate_capacity_provider_name
}

output "fargate_spot_capacity_provider_name" {
  description = "The name of the Fargate Spot capacity provider."
  value       = module.ecs_cluster.fargate_spot_capacity_provider_name
}
