################################################################################
# Aurora Full Fixture
#
# An Aurora PostgreSQL cluster with all features enabled for Terratest
# integration testing. Tests custom endpoints, autoscaling, monitoring,
# CloudWatch alarms, parameter groups, and multiple readers.
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
  subnet_count = 3

  tags = local.common_tags
}

################################################################################
# Aurora Cluster — Full Featured
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
  database_name   = "testdb"

  # Security
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

  # Monitoring — Enhanced Monitoring + CloudWatch Logs
  monitoring_interval             = 60
  create_monitoring_role          = true
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # CloudWatch Alarms
  create_cloudwatch_alarms = true

  # Parameter groups with custom parameters
  cluster_parameter_group_family = "aurora-postgresql16"
  cluster_parameters = [
    {
      name         = "log_min_duration_statement"
      value        = "1000"
      apply_method = "immediate"
    }
  ]

  db_parameter_group_family = "aurora-postgresql16"

  # Auto-scaling
  enable_autoscaling             = true
  autoscaling_min_capacity       = 1
  autoscaling_max_capacity       = 3
  autoscaling_target_cpu         = 70
  autoscaling_target_connections = 100

  # Custom endpoints
  custom_endpoints = {
    analytics = {
      type             = "READER"
      excluded_members = []
    }
  }

  # Test-friendly settings
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  apply_immediately       = true

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

output "instance_endpoints" {
  description = "Map of instance key to instance endpoint."
  value       = module.aurora.instance_endpoints
}

output "security_group_id" {
  description = "The ID of the Aurora security group."
  value       = module.aurora.security_group_id
}

output "cluster_parameter_group_name" {
  description = "The name of the cluster parameter group."
  value       = module.aurora.cluster_parameter_group_name
}

output "db_parameter_group_name" {
  description = "The name of the DB parameter group."
  value       = module.aurora.db_parameter_group_name
}

output "enhanced_monitoring_iam_role_arn" {
  description = "The ARN of the Enhanced Monitoring IAM role."
  value       = module.aurora.enhanced_monitoring_iam_role_arn
}

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs."
  value       = module.aurora.cloudwatch_alarm_arns
}

output "custom_endpoint_arns" {
  description = "Map of custom endpoint ARNs."
  value       = module.aurora.custom_endpoint_arns
}

output "autoscaling_target_arn" {
  description = "The ARN of the auto-scaling target."
  value       = module.aurora.autoscaling_target_arn
}
