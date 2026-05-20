provider "aws" {
  region = var.region
}

# Cloudflare provider — used only when the parent cluster's
# DnsProvider is CLOUDFLARE (count gating on
# `data.ravion_dns_provider.this[0].cloudflare` in ravion_domains.tf).
# Same api_token resolution path as the cluster module: WorkOS Vault
# deref via Ravion's data source.
provider "cloudflare" {
  api_token = try(data.ravion_dns_provider.this[0].cloudflare.api_token, null)
}
