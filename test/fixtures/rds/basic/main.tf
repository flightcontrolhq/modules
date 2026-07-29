################################################################################
# RDS Basic Fixture
#
# A minimal PostgreSQL RDS instance for Terratest integration testing.
# Creates a VPC and deploys a single db.t3.micro instance with test-friendly
# lifecycle settings.
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
  vpc_cidr     = "10.1.0.0/16"
  subnet_count = 2

  tags = local.common_tags
}

################################################################################
# RDS Instance
################################################################################

module "rds" {
  source = "../../../../database/rds"

  name                 = var.name
  engine               = "postgres"
  engine_major_version = "16"
  engine_minor_version = "6"
  instance_class       = "db.t3.micro"

  allocated_storage      = 20
  parameter_group_family = "postgres16"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "dbadmin"
  db_name  = "testdb"

  security_group_creation_enabled = true
  allowed_cidr_blocks             = [module.vpc.vpc_cidr_block]

  # Test-friendly lifecycle settings.
  deletion_protection_enabled     = false
  final_snapshot_creation_enabled = false
  backup_retention_period         = 1
  immediate_apply_enabled         = true
  performance_insights_enabled    = false

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "db_instance_identifier" {
  description = "RDS instance identifier."
  value       = module.rds.db_instance_identifier
}

output "db_instance_arn" {
  description = "RDS instance ARN."
  value       = module.rds.db_instance_arn
}

output "db_instance_status" {
  description = "RDS instance status."
  value       = module.rds.db_instance_status
}

output "engine" {
  description = "RDS instance engine."
  value       = module.rds.engine
}

output "address" {
  description = "RDS endpoint address."
  value       = module.rds.address
}

output "port" {
  description = "RDS endpoint port."
  value       = module.rds.port
}

output "db_parameter_group_name" {
  description = "RDS DB parameter group name."
  value       = module.rds.db_parameter_group_name
}

output "security_group_id" {
  description = "RDS security group ID."
  value       = module.rds.security_group_id
}
