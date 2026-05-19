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
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = ">= 1.0.0"
    }
  }
}
