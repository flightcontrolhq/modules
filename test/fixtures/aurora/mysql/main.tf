################################################################################
# Aurora MySQL Fixture
#
# An Aurora MySQL cluster for Terratest integration testing. Tests
# MySQL-specific features: backtrack and local write forwarding.
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
# Aurora MySQL Cluster
################################################################################

module "aurora" {
  source = "../../../../database/aurora"

  name           = var.name
  engine         = "aurora-mysql"
  engine_version = "8.0.mysql_aurora.3.08.0"
  instance_class = "db.t4g.medium"
  reader_count   = 1

  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Authentication
  master_username = "testadmin"
  database_name   = "testdb"

  # MySQL-specific features
  backtrack_window              = 3600 # 1 hour
  enable_local_write_forwarding = true

  # CloudWatch Logs (MySQL types)
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # Security
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

  # Parameter groups
  cluster_parameter_group_family = "aurora-mysql8.0"
  db_parameter_group_family      = "aurora-mysql8.0"

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

output "cluster_arn" {
  description = "The ARN of the Aurora cluster."
  value       = module.aurora.cluster_arn
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

output "cluster_database_name" {
  description = "The database name."
  value       = module.aurora.cluster_database_name
}

output "cluster_parameter_group_name" {
  description = "The name of the cluster parameter group."
  value       = module.aurora.cluster_parameter_group_name
}

output "security_group_id" {
  description = "The ID of the Aurora security group."
  value       = module.aurora.security_group_id
}
