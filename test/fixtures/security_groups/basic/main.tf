################################################################################
# Security Groups Basic Fixture
#
# A minimal security group configuration for Terratest integration testing.
# Creates a VPC first, then deploys a security group with sample ingress rules
# for SSH (port 22) and HTTP (port 80).
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
# Security Group
################################################################################

module "security_group" {
  source = "../../../../networking/security-groups"

  name        = var.name
  name_suffix = "test"
  description = "Terratest security group with SSH and HTTP access"
  vpc_id      = module.vpc.vpc_id

  # Sample ingress rules for SSH (22) and HTTP (80)
  ingress_rules = [
    {
      description = "SSH access from anywhere"
      from_port   = 22
      to_port     = 22
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    {
      description = "HTTP access from anywhere"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  ]

  # Allow all outbound traffic
  allow_all_egress = true

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "security_group_id" {
  description = "The ID of the security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = module.security_group.security_group_arn
}

output "security_group_name" {
  description = "The name of the security group."
  value       = module.security_group.security_group_name
}
