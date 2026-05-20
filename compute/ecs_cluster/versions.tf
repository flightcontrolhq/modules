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
    # Bumped to v2 — the V2 provider drops the `ravion_dns_zone_id`
    # field name in favor of `ravion_dns_provider_id`, and exposes
    # the new `data.ravion_dns_provider` discriminated data source
    # that this module's per-variant HCL gates on.
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = ">= 2.0.0"
    }
    # Cloudflare provider is needed when the registered DnsProvider
    # is CLOUDFLARE — the customer's TF writes acme validation +
    # apex routing records via `cloudflare_record`, and Ravion
    # records them after-the-fact via `ravion_dns_records` for the
    # UI. 
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }
}
