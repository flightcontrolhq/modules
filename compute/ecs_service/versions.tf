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
    # See compute/ecs_cluster/versions.tf for rationale on dropping
    # cloudflare/cloudflare — the ravion_dns_records resource is now
    # SDK-backed server-side.
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = ">= 2.0.0"
    }
  }
}
