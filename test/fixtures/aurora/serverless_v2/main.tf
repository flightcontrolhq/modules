################################################################################
# Aurora Serverless v2 Fixture
#
# An Aurora PostgreSQL cluster with Serverless v2 scaling for Terratest
# integration testing. Verifies that the module correctly configures
# serverless scaling and uses db.serverless instance class.
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
# Aurora Cluster — Serverless v2
################################################################################

module "aurora" {
  source = "../../../../database/aurora"

  name           = var.name
  engine         = "aurora-postgresql"
  engine_version = "16.6"
  instance_class = "db.serverless"
  reader_count   = 1

  # Serverless v2 scaling configuration
  serverless_v2_scaling = {
    min_capacity = 0.5
    max_capacity = 2.0
  }

  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Authentication
  master_username = "testadmin"

  # Security
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

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

output "cluster_reader_endpoint" {
  description = "The reader endpoint for the Aurora cluster."
  value       = module.aurora.cluster_reader_endpoint
}

output "cluster_port" {
  description = "The port on which the Aurora cluster accepts connections."
  value       = module.aurora.cluster_port
}

output "instance_identifiers" {
  description = "Map of instance key to instance identifier."
  value       = module.aurora.instance_identifiers
}

output "cluster_engine_version_actual" {
  description = "The actual engine version running on the cluster."
  value       = module.aurora.cluster_engine_version_actual
}

output "security_group_id" {
  description = "The ID of the Aurora security group."
  value       = module.aurora.security_group_id
}
