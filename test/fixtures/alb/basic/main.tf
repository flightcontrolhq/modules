################################################################################
# ALB Basic Fixture
#
# A minimal ALB configuration for Terratest integration testing.
# Creates a VPC first, then deploys an internet-facing ALB with HTTP listener.
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
# ALB
################################################################################

module "alb" {
  source = "../../../../networking/alb"

  name       = var.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Basic HTTP-only configuration
  enable_http_listener  = true
  enable_https_listener = false

  # Disable deletion protection for test cleanup
  enable_deletion_protection = false

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer."
  value       = module.alb.alb_arn
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = module.alb.alb_dns_name
}

output "security_group_id" {
  description = "The ID of the ALB security group."
  value       = module.alb.security_group_id
}

output "http_listener_arn" {
  description = "The ARN of the HTTP listener."
  value       = module.alb.http_listener_arn
}
