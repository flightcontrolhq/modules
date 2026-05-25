terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # Optional — only used when `ravion_dns_provider_id` is set. The
    # resources in `ravion_domain.tf` count out to zero when the input
    # is null, so a consumer that doesn't opt in still doesn't need
    # the provider configured. Constraint matches sibling modules.
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = ">= 2.0.0"
    }
  }
}
