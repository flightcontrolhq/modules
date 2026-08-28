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
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    # DEMO BRANCH: the ravion provider (beacon credential minting) is stripped —
    # the dev API this branch deploys against has no beacon endpoints yet, and
    # the demo runs with beacon disabled. Restore the provider (and beacon.tf's
    # real resource) when the API side lands.
  }
}
