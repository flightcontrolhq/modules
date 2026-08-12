################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # Ravion domains provider — only exercised when
    # var.use_ravion_managed_domains = true (see ravion_domains.tf).
    ravion = {
      source  = "d39sxny1zxb1eh.cloudfront.net/ravion/ravion"
      version = "0.0.1-rc.1"
    }
  }
}
