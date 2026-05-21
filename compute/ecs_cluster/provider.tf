provider "aws" {
  region = var.region
}

# Cloudflare provider — token comes from the first cert-group whose
# DnsProvider resolves to a CLOUDFLARE variant. Null when no cert
# group is using Cloudflare; no cloudflare_* resources will plan in
# that case so the provider stays inert.
provider "cloudflare" {
  api_token = module.ravion_cert_groups.cloudflare_api_token
}
