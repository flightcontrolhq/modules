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
    # The V2 provider exposes `data.ravion_dns_provider` (discriminated
    # data source) + `ravion_dns_records` (now SDK-backed: when the
    # api-go side has a real writer for the provider type, the resource
    # write triggers the real DNS write via the api-go's per-provider
    # SDK — no per-provider HCL needed here).
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = ">= 2.0.0"
    }
  }
}
