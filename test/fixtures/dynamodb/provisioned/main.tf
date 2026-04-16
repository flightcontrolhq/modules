################################################################################
# DynamoDB Provisioned + Autoscaling Fixture
#
# Provisioned DynamoDB table with Application Auto Scaling on read and write
# capacity.
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

  name         = var.name
  hash_key     = "order_id"
  billing_mode = "PROVISIONED"

  attributes     = [{ name = "order_id", type = "S" }]
  read_capacity  = 5
  write_capacity = 5

  autoscaling_enabled = true
  autoscaling_read    = { min_capacity = 5, max_capacity = 20 }
  autoscaling_write   = { min_capacity = 5, max_capacity = 20 }

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

output "billing_mode" {
  description = "The billing mode of the DynamoDB table."
  value       = module.dynamodb.billing_mode
}

output "autoscaling_table_read_target_arn" {
  description = "ARN of the read-capacity autoscaling target."
  value       = module.dynamodb.autoscaling_table_read_target_arn
}

output "autoscaling_table_write_target_arn" {
  description = "ARN of the write-capacity autoscaling target."
  value       = module.dynamodb.autoscaling_table_write_target_arn
}
