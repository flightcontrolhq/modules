################################################################################
# DynamoDB With GSI/LSI and Streams Fixture
#
# On-demand DynamoDB table with one GSI, one LSI, TTL, and DynamoDB Streams.
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

  name      = var.name
  hash_key  = "user_id"
  range_key = "created_at"

  attributes = [
    { name = "user_id", type = "S" },
    { name = "created_at", type = "N" },
    { name = "event_type", type = "S" },
  ]

  global_secondary_indexes = [
    {
      name            = "by_event_type"
      hash_key        = "event_type"
      range_key       = "created_at"
      projection_type = "ALL"
    },
  ]

  local_secondary_indexes = [
    {
      name            = "by_user_event_type"
      range_key       = "event_type"
      projection_type = "KEYS_ONLY"
    },
  ]

  ttl_enabled        = true
  ttl_attribute_name = "expires_at"

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery_enabled = false

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

output "stream_arn" {
  description = "The ARN of the DynamoDB Stream."
  value       = module.dynamodb.stream_arn
}

output "global_secondary_index_names" {
  description = "Names of the GSIs."
  value       = module.dynamodb.global_secondary_index_names
}

output "local_secondary_index_names" {
  description = "Names of the LSIs."
  value       = module.dynamodb.local_secondary_index_names
}
