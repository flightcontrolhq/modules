################################################################################
# IAM Role with OIDC Provider Fixture
#
# Creates an IAM role with OIDC provider trust for testing.
# This fixture creates both the OIDC provider (GitHub Actions pattern) and
# an IAM role that trusts it.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
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

variable "github_org" {
  type        = string
  description = "GitHub organization name for OIDC trust."
  default     = "test-org"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name for OIDC trust."
  default     = "test-repo"
}

locals {
  common_tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )

  github_actions_oidc_url = "https://token.actions.githubusercontent.com"
}

################################################################################
# GitHub Actions OIDC Provider
#
# Creates the OIDC provider for GitHub Actions. In production, this would
# typically be created once per AWS account, but for testing we create it
# as part of the fixture.
################################################################################

data "tls_certificate" "github_actions" {
  url = local.github_actions_oidc_url
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = local.github_actions_oidc_url

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = merge(local.common_tags, {
    Name = "${var.name}-github-actions-oidc"
  })
}

################################################################################
# IAM Role with OIDC Trust
################################################################################

module "iam_role" {
  source = "../../../../security/iam"

  name        = var.name
  description = "Terratest IAM role with GitHub Actions OIDC trust"
  path        = "/test/"

  # Trust GitHub Actions OIDC provider
  trusted_oidc_providers = [
    {
      provider_arn = aws_iam_openid_connect_provider.github_actions.arn
      conditions = [
        {
          test     = "StringEquals"
          variable = "token.actions.githubusercontent.com:aud"
          values   = ["sts.amazonaws.com"]
        },
        {
          test     = "StringLike"
          variable = "token.actions.githubusercontent.com:sub"
          values   = ["repo:${var.github_org}/${var.github_repo}:*"]
        }
      ]
    }
  ]

  tags = local.common_tags

  depends_on = [aws_iam_openid_connect_provider.github_actions]
}

################################################################################
# Outputs
################################################################################

# IAM Role Outputs
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

# OIDC Provider Outputs
output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "oidc_provider_url" {
  description = "The URL of the OIDC provider."
  value       = aws_iam_openid_connect_provider.github_actions.url
}

# Instance Profile Outputs (null for OIDC fixture)
output "instance_profile_arn" {
  description = "The ARN of the instance profile (null in OIDC fixture)."
  value       = module.iam_role.instance_profile_arn
}

# Policy Outputs
output "managed_policy_arns" {
  description = "List of managed policy ARNs attached."
  value       = module.iam_role.managed_policy_arns
}

output "inline_policy_names" {
  description = "List of inline policy names attached."
  value       = module.iam_role.inline_policy_names
}
