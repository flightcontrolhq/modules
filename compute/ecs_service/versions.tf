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
    # Used only when var.domains is non-empty — declares one
    # domains_module_certificate per call so Ravion's reconciler can issue +
    # attach a per-service cert as SNI on the cluster's HTTPS listener.
    domains = {
      source  = "ravion.com/ravion/domains"
      version = "~> 0.1"
    }
  }
}


