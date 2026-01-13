################################################################################
# IAM Role Basic Fixture
#
# A minimal IAM role configuration for Terratest integration testing.
# Creates an IAM role with a trusted service (ec2.amazonaws.com) and basic tags.
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
# IAM Role
################################################################################

module "iam_role" {
  source = "../../../../security/iam"

  name        = var.name
  description = "Terratest basic IAM role for EC2"
  path        = "/test/"

  # Trust EC2 service to assume this role
  trusted_services = ["ec2.amazonaws.com"]

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "role_arn" {
  description = "The ARN of the IAM role."
  value       = module.iam_role.role_arn
}

output "role_name" {
  description = "The name of the IAM role."
  value       = module.iam_role.role_name
}

output "role_id" {
  description = "The ID of the IAM role."
  value       = module.iam_role.role_id
}

output "role_path" {
  description = "The path of the IAM role."
  value       = module.iam_role.role_path
}

output "role_unique_id" {
  description = "The unique ID of the IAM role."
  value       = module.iam_role.role_unique_id
}

output "instance_profile_arn" {
  description = "The ARN of the instance profile (null in basic fixture)."
  value       = module.iam_role.instance_profile_arn
}

output "managed_policy_arns" {
  description = "List of managed policy ARNs attached."
  value       = module.iam_role.managed_policy_arns
}

output "inline_policy_names" {
  description = "List of inline policy names attached."
  value       = module.iam_role.inline_policy_names
}
