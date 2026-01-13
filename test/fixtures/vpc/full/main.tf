################################################################################
# VPC Full-Featured Fixture
#
# A full-featured VPC configuration for Terratest integration testing.
# Creates a VPC with public and private subnets across 3 AZs with:
# - High availability NAT Gateways (one per AZ)
# - IPv6 support
# - VPC Flow Logs to CloudWatch
################################################################################

terraform {
  required_version = ">= 1.0"

  # Use local backend with configurable path for test isolation
  # Each parallel test can specify a unique state file via -backend-config="path=..."
  backend "local" {}

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

  # High availability NAT Gateways (one per AZ)
  enable_nat_gateway = true
  single_nat_gateway = false

  # IPv6 support
  enable_ipv6 = true

  # VPC Flow Logs to CloudWatch
  enable_flow_logs         = true
  flow_logs_destination    = "cloudwatch"
  flow_logs_retention_days = 7

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

output "vpc_cidr_block" {
  description = "The IPv4 CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block of the VPC."
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ipv6_cidrs" {
  description = "List of IPv6 CIDR blocks of public subnets."
  value       = module.vpc.public_subnet_ipv6_cidrs
}

output "private_subnet_ipv6_cidrs" {
  description = "List of IPv6 CIDR blocks of private subnets."
  value       = module.vpc.private_subnet_ipv6_cidrs
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

output "egress_only_internet_gateway_id" {
  description = "The ID of the Egress-Only Internet Gateway for IPv6."
  value       = module.vpc.egress_only_internet_gateway_id
}

output "flow_log_id" {
  description = "The ID of the VPC Flow Log."
  value       = module.vpc.flow_log_id
}

output "flow_log_cloudwatch_log_group_name" {
  description = "The name of the CloudWatch Log Group for VPC Flow Logs."
  value       = module.vpc.flow_log_cloudwatch_log_group_name
}

output "flow_log_cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch Log Group for VPC Flow Logs."
  value       = module.vpc.flow_log_cloudwatch_log_group_arn
}
