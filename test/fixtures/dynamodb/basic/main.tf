################################################################################
# DynamoDB Basic Fixture
#
# Minimal on-demand DynamoDB table for Terratest integration testing.
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
    var.tags,
  )
}

module "dynamodb" {
  source = "../../../../database/dynamodb"

  name     = var.name
  hash_key = "session_id"

  attributes = [
    { name = "session_id", type = "S" },
  ]

  ttl_enabled        = true
  ttl_attribute_name = "expires_at"

  point_in_time_recovery_enabled = false # faster destroy in tests

  tags = local.common_tags
}

output "table_name" {
  description = "The name of the DynamoDB table."
  value       = module.dynamodb.table_name
}

output "table_arn" {
  description = "The ARN of the DynamoDB table."
  value       = module.dynamodb.table_arn
}

output "billing_mode" {
  description = "The billing mode of the DynamoDB table."
  value       = module.dynamodb.billing_mode
}

output "table_hash_key" {
  description = "The hash key of the DynamoDB table."
  value       = module.dynamodb.table_hash_key
}
