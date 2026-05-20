provider "aws" {
  region = var.region
}

# Cloudflare provider — used only when the registered DnsProvider is
# CLOUDFLARE (count gating on `data.ravion_dns_provider.this[0].cloudflare`
# in ravion_domains.tf decides whether any `cloudflare_record` resources
# are actually planned).
#
# When the DnsProvider is anything other than CLOUDFLARE the data
# source's cloudflare attribute is null; the provider config still
# evaluates but no `cloudflare_record` resources reference it (count = 0).
provider "cloudflare" {
  api_token = try(data.ravion_dns_provider.this[0].cloudflare.api_token, null)
}
