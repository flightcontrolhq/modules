provider "aws" {
  region = var.region
}

# Cloudflare token sourced from any customer cert-group whose provider
# is Cloudflare. Null when none — provider stays inert.
provider "cloudflare" {
  api_token = module.ravion_cert_groups.cloudflare_api_token
}
