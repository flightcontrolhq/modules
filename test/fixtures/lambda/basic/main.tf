################################################################################
# Lambda Basic Fixture
#
# A minimal ZIP-based Lambda function for Terratest integration testing.
# The deployment package is generated on the fly via archive provider.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
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

data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/function.zip"

  source {
    content  = <<-EOT
      exports.handler = async () => {
        return {
          statusCode: 200,
          body: "ok"
        };
      };
    EOT
    filename = "index.js"
  }
}

################################################################################
# Lambda Function
################################################################################

module "lambda" {
  source = "../../../../compute/lambda"

  name = var.name

  package_type = "Zip"
  runtime      = "nodejs20.x"
  handler      = "index.handler"

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  timeout     = 10
  memory_size = 128

  create_role = true

  function_url_enabled   = true
  function_url_auth_type = "AWS_IAM"

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "function_name" {
  description = "Lambda function name."
  value       = module.lambda.function_name
}

output "function_arn" {
  description = "Lambda function ARN."
  value       = module.lambda.function_arn
}

output "role_arn" {
  description = "IAM role ARN used by Lambda."
  value       = module.lambda.role_arn
}

output "function_url" {
  description = "Lambda function URL."
  value       = module.lambda.function_url
}
