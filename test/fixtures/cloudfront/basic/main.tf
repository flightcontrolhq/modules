################################################################################
# CloudFront Basic Fixture
#
# A minimal CloudFront distribution for Terratest integration testing.
# Uses a simple custom origin and default CloudFront certificate to avoid
# external certificate dependencies.
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
# CloudFront Distribution
################################################################################

module "cloudfront" {
  source = "../../../../cdn/cloudfront"

  name = var.name

  distributions = {
    main = {}
  }

  origins = [
    {
      origin_id   = "custom-origin"
      domain_name = "example.com"
      s3_origin   = false
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "custom-origin"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  wait_for_deployment = false
  tags                = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.cloudfront.distribution_ids["main"]
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = module.cloudfront.distribution_arns["main"]
}

output "distribution_domain_name" {
  description = "CloudFront distribution domain name."
  value       = module.cloudfront.distribution_domain_names["main"]
}

output "distribution_status" {
  description = "CloudFront distribution status."
  value       = module.cloudfront.distribution_statuses["main"]
}
