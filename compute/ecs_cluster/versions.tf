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
    # Forwarded to the networking/alb child module. Only actually evaluated
    # at apply time when var.use_ravion_managed_domains = true.
    domains = {
      source  = "ravion.com/ravion/domains"
      version = "~> 0.1"
    }
  }
}


