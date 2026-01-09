################################################################################
# VPC with Flow Logs to S3 Fixture
#
# A VPC configuration for Terratest integration testing with VPC Flow Logs
# sent to an S3 bucket. This fixture tests the S3 flow logs destination.
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
  subnet_count = 2

  # VPC Flow Logs to S3
  enable_flow_logs         = true
  flow_logs_destination    = "s3"
  flow_logs_retention_days = 30

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

output "flow_log_id" {
  description = "The ID of the VPC Flow Log."
  value       = module.vpc.flow_log_id
}

output "flow_log_s3_bucket_arn" {
  description = "The ARN of the S3 bucket for VPC Flow Logs."
  value       = module.vpc.flow_log_s3_bucket_arn
}
