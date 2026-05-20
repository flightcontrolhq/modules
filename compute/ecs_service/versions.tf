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
    # Bumped to v2 — see compute/ecs_cluster/versions.tf for rationale.
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = ">= 2.0.0"
    }
    # Cloudflare provider for per-service CNAMEs when the parent
    # cluster's DnsProvider is CLOUDFLARE. Count-gated in
    # ravion_domains.tf — no cloudflare_record resources plan when
    # the provider variant is different.
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }
}
