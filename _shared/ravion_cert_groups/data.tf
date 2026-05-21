################################################################################
# Per-cert-group DnsProvider resolution.
#
# `customer` groups carry their own provider on the row (id or
# given_id; id wins). Non-customer kinds (`ravion_auto`) fall back to
# the cluster's provider (var.ravion_dns_provider_id) so the data
# source still resolves to a usable variant for downstream variant
# dispatch (route53_ravion / route53 / cloudflare).
################################################################################

data "ravion_dns_provider" "groups" {
  for_each = { for g in var.cert_groups : g.name => g }

  id = (
    each.value.kind == "customer"
    ? coalesce(each.value.dns_provider_id, "") != "" ? each.value.dns_provider_id : null
    : var.ravion_dns_provider_id
  )

  given_id = (
    each.value.kind == "customer" && coalesce(each.value.dns_provider_id, "") == ""
    ? each.value.dns_provider_given_id
    : null
  )
}

# Parent mode + kind=ravion_auto looks up the platform-apex DnsProvider
# so the wildcard is allocated under the right zone. Count-gated so
# leaf-mode + non-ravion_auto parent groups don't pay the lookup.
data "ravion_dns_provider" "platform_apex" {
  count    = var.mode == "parent" && length([for g in var.cert_groups : g if g.kind == "ravion_auto"]) > 0 ? 1 : 0
  given_id = var.platform_apex_provider_given_id
}
