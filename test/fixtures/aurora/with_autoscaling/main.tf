################################################################################
# Aurora with Autoscaling Fixture
#
# An Aurora PostgreSQL cluster with read replica auto-scaling for Terratest
# integration testing. Verifies that auto-scaling target and CPU/connection
# policies are created correctly.
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
# Aurora Cluster with Auto-scaling
################################################################################

module "aurora" {
  source = "../../../../database/aurora"

  name           = var.name
  engine         = "aurora-postgresql"
  engine_version = "16.6"
  instance_class = "db.t4g.medium"
  reader_count   = 1

  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Authentication
  master_username = "testadmin"

  # Security
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

  # Auto-scaling — CPU and connection-based policies
  enable_autoscaling             = true
  autoscaling_min_capacity       = 1
  autoscaling_max_capacity       = 3
  autoscaling_target_cpu         = 70
  autoscaling_target_connections = 100
  autoscaling_scale_in_cooldown  = 300
  autoscaling_scale_out_cooldown = 300

  # Test-friendly settings
  deletion_protection          = false
  skip_final_snapshot          = true
  backup_retention_period      = 1
  apply_immediately            = true
  performance_insights_enabled = false

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "cluster_id" {
  description = "The ID of the Aurora cluster."
  value       = module.aurora.cluster_id
}

output "cluster_endpoint" {
  description = "The writer endpoint for the Aurora cluster."
  value       = module.aurora.cluster_endpoint
}

output "instance_identifiers" {
  description = "Map of instance key to instance identifier."
  value       = module.aurora.instance_identifiers
}

output "autoscaling_target_arn" {
  description = "The ARN of the auto-scaling target."
  value       = module.aurora.autoscaling_target_arn
}

output "security_group_id" {
  description = "The ID of the Aurora security group."
  value       = module.aurora.security_group_id
}
