################################################################################
# ElastiCache Redis Replication Fixture
#
# An ElastiCache Redis cluster with replication (1 primary + 1 replica) for
# Terratest integration testing. Verifies that the module correctly creates
# Redis replication groups with multiple nodes.
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
# ElastiCache Redis with Replication
################################################################################

module "elasticache" {
  source = "../../../../cache/elasticache"

  name   = var.name
  vpc_id = module.vpc.vpc_id

  # Use private subnets for ElastiCache
  subnet_ids = module.vpc.private_subnet_ids

  # Redis configuration
  engine    = "redis"
  node_type = "cache.t4g.micro"

  # Replication configuration: 1 primary + 1 replica = 2 nodes
  replicas_per_node_group = 1

  # Disable cluster mode for simple replication testing
  cluster_mode_enabled = false

  # Enable automatic failover (required for replicas)
  automatic_failover_enabled = true

  # Enable Multi-AZ for high availability
  multi_az_enabled = true

  # Security - create a security group that allows access from VPC CIDR
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

  # Disable encryption for simpler testing (faster provisioning)
  transit_encryption_enabled = false
  at_rest_encryption_enabled = false

  # Disable snapshots for testing
  snapshot_retention_limit = 0

  # Apply changes immediately for testing
  apply_immediately = true

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "replication_group_id" {
  description = "The ID of the ElastiCache replication group."
  value       = module.elasticache.replication_group_id
}

output "replication_group_arn" {
  description = "The ARN of the ElastiCache replication group."
  value       = module.elasticache.replication_group_arn
}

output "primary_endpoint" {
  description = "The address of the primary endpoint for the Redis cluster."
  value       = module.elasticache.primary_endpoint_address
}

output "reader_endpoint" {
  description = "The address of the reader endpoint for the Redis cluster."
  value       = module.elasticache.reader_endpoint_address
}

output "port" {
  description = "The port number on which the cache accepts connections."
  value       = module.elasticache.port
}

output "security_group_id" {
  description = "The ID of the ElastiCache security group."
  value       = module.elasticache.security_group_id
}

output "subnet_group_name" {
  description = "The name of the ElastiCache subnet group."
  value       = module.elasticache.subnet_group_name
}
