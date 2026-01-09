################################################################################
# VPC with NAT Gateway Fixture
#
# A VPC configuration with NAT Gateway enabled for Terratest integration testing.
# Creates a VPC with public and private subnets across 3 AZs with a single NAT
# Gateway for private subnet internet access.
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

module "vpc" {
  source = "../../../../networking/vpc"

  name         = var.name
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 3

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets."
  value       = module.vpc.private_subnet_ids
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway."
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs."
  value       = module.vpc.nat_gateway_ids
}

output "nat_gateway_public_ips" {
  description = "List of public IP addresses of NAT Gateways."
  value       = module.vpc.nat_gateway_public_ips
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables."
  value       = module.vpc.private_route_table_ids
}
