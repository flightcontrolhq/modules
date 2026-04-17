################################################################################
# Example: filesystem_previews mode
#
# Provisions a Flightcontrol-equivalent static site stack: private S3 hosting
# bucket, CloudFront distribution with OAC, CloudFront Function for host ->
# deployment-prefix lookup via KeyValueStore, and a Lambda@Edge handler for
# filesystem-style path resolution and custom 404 pages.
#
# Apply notes:
#   - npm must be available on the machine running `tofu apply` (used to install
#     dependencies for the bundled Lambda@Edge handler).
#   - Lambda@Edge functions must live in us-east-1; the us_east_1 alias is
#     wired through to the composite.
#   - This example creates a deploy role assuming GitHub OIDC.
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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "site" {
  source = "../.."

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "ravion-example-site"
  mode = "filesystem_previews"

  distributions = {
    main = {
      aliases             = ["app.example.com", "*.preview.example.com"]
      acm_certificate_arn = var.acm_certificate_arn
      comment             = "Example site"
    }
  }

  static_mode_header_value   = "filesystem"
  deployment_id_header_value = "main"
  trailing_slash_enabled     = true

  long_cache_paths = ["/_astro/*", "/assets/*"]

  create_key_value_store = true
  kvs_initial_data = {
    "pr-42.preview.example.com" = "versions/pr-42"
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

output "deploy_command" {
  value = module.site.invalidation_commands["main"]
}
