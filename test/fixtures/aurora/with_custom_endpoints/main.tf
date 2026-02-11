################################################################################
# Aurora with Custom Endpoints Fixture
#
# An Aurora PostgreSQL cluster with custom endpoints for Terratest integration
# testing. Verifies that custom READER and ANY endpoints are created correctly
# with static and excluded member configurations.
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
# Aurora Cluster with Custom Endpoints
################################################################################

module "aurora" {
  source = "../../../../database/aurora"

  name           = var.name
  engine         = "aurora-postgresql"
  engine_version = "16.6"
  instance_class = "db.t4g.medium"
  reader_count   = 2

  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Authentication
  master_username = "testadmin"

  # Security
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

  # Custom endpoints
  custom_endpoints = {
    analytics = {
      type             = "READER"
      excluded_members = []
    }
    reporting = {
      type             = "ANY"
      excluded_members = []
    }
  }

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

output "instance_identifiers" {
  description = "Map of instance key to instance identifier."
  value       = module.aurora.instance_identifiers
}

output "custom_endpoint_arns" {
  description = "Map of custom endpoint ARNs."
  value       = module.aurora.custom_endpoint_arns
}

output "security_group_id" {
  description = "The ID of the Aurora security group."
  value       = module.aurora.security_group_id
}
