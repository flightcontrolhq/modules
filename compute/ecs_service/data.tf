################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# Resolve the registered Ravion DnsProvider — same shape as the
# cluster module's data block. Per-variant attribute groups
# (`route53_ravion`, `route53`, `cloudflare`, `external`) drive the
# count gating in ravion_domains.tf. Skipped (count = 0) when no
# provider is configured at the service level, which is the common
# case — services typically inherit the cluster's wildcard via the
# parent_domain_allocation_id link and don't need to dispatch on
# variant themselves except for the routing CNAME write path.
data "ravion_dns_provider" "this" {
  count    = local.dns_provider_lookup_key == "" ? 0 : 1
  id       = var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != "" ? var.ravion_dns_provider_id : null
  given_id = var.ravion_dns_provider_given_id != null && var.ravion_dns_provider_given_id != "" ? var.ravion_dns_provider_given_id : null
}

# Per-cert-group DnsProvider lookups. Each group can target a different
# provider than the service's top-level one (multi-zone setups, e.g.
# acme.com on Cloudflare + app.acme.com on Route53). Falls back to the
# service-level provider when the group doesn't specify its own.
data "ravion_dns_provider" "groups" {
  for_each = { for g in var.ravion_certificate_groups : g.name => g }

  id = coalesce(
    each.value.dns_provider_id,
    var.ravion_dns_provider_id,
    "",
  ) != "" ? coalesce(each.value.dns_provider_id, var.ravion_dns_provider_id) : null

  given_id = coalesce(
    each.value.dns_provider_id,
    var.ravion_dns_provider_id,
    "",
    ) != "" ? null : coalesce(
    each.value.dns_provider_given_id,
    var.ravion_dns_provider_given_id,
  )
}


