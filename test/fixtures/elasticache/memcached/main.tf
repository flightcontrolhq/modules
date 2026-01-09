################################################################################
# ElastiCache Memcached Fixture
#
# A minimal ElastiCache Memcached cluster configuration for Terratest integration
# testing. Creates a VPC, security group, subnet group, and Memcached cluster
# (cache.t4g.micro, single node for cost efficiency).
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
# ElastiCache Memcached
################################################################################

module "elasticache" {
  source = "../../../../cache/elasticache"

  name   = var.name
  vpc_id = module.vpc.vpc_id

  # Use private subnets for ElastiCache
  subnet_ids = module.vpc.private_subnet_ids

  # Memcached configuration
  engine    = "memcached"
  node_type = "cache.t4g.micro"

  # Single node for cost efficiency in testing
  num_cache_nodes = 1

  # Security - create a security group that allows access from VPC CIDR
  create_security_group = true
  allowed_cidr_blocks   = [module.vpc.vpc_cidr_block]

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

output "cluster_id" {
  description = "The ID of the ElastiCache Memcached cluster."
  value       = module.elasticache.cluster_id
}

output "cluster_arn" {
  description = "The ARN of the ElastiCache Memcached cluster."
  value       = module.elasticache.cluster_arn
}

output "cluster_address" {
  description = "The DNS name of the Memcached cluster without the port."
  value       = module.elasticache.cluster_address
}

output "configuration_endpoint" {
  description = "The configuration endpoint for the Memcached cluster."
  value       = module.elasticache.configuration_endpoint
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
