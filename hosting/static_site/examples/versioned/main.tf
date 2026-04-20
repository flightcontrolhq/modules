################################################################################
# Example: versioned static site with PR previews and instant rollback.
#
# Provisions a private S3 hosting bucket, a CloudFront distribution with OAC,
# a CloudFront KeyValueStore, and a viewer-request rewriter function.
#
# Deploy and rollback are CI-driven via the KVS:
#   VERSION="v$(git rev-parse --short HEAD)"
#   aws s3 sync ./dist s3://${hosting_bucket}/$VERSION/ --delete
#   # then run the set_active_version_command output to flip 'active'
#
# Per-host overrides (PR previews):
#   aws cloudfront-keyvaluestore put-key \
#     --kvs-arn $KVS_ARN --if-match $ETAG \
#     --key pr-42.preview.example.com --value v_pr-42
################################################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "site" {
  source = "../.."

  name    = "ravion-example-site"
  routing = "filesystem"

  distributions = {
    main = {
      aliases             = ["app.example.com", "*.preview.example.com"]
      acm_certificate_arn = var.acm_certificate_arn
      comment             = "Example site"
    }
  }

  long_cache_paths = ["/_astro/*", "/assets/*"]

  # Pin staging to a specific version while production tracks 'active'.
  kvs_initial_data = {
    "staging.example.com" = "v_staging"
  }

  create_deploy_role = true
  deploy_role_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:my-org/my-repo:*"
        }
      }
    }]
  })

  tags = {
    Environment = "example"
    ManagedBy   = "tofu"
  }
}

data "aws_caller_identity" "current" {}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 covering the configured aliases."
}

output "hosting_bucket" {
  value = module.site.hosting_bucket_id
}

output "distribution_domain_name" {
  value = module.site.distribution_domain_names["main"]
}

output "deploy_role_arn" {
  value = module.site.deploy_role_arn
}

output "key_value_store_arn" {
  value = module.site.key_value_store_arn
}

output "set_active_version_command" {
  value = module.site.set_active_version_command
}
