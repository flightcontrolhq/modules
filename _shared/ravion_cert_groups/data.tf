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
