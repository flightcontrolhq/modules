################################################################################
# Per-cert-group DnsProvider resolution.
#
# `customer` groups carry their own provider on the row (id or
# given_id; id wins). Non-customer kinds (`ravion_auto`) fall back to
# the cluster's provider (var.ravion_dns_provider_id) so the data
# source still resolves to a usable variant for downstream variant
# dispatch (route53_ravion / route53 / cloudflare).
################################################################################

# Only iterates over groups that need their OWN DnsProvider row.
# `ravion_auto` skips this lookup — it uses data.platform_apex below.
# `inherit` (leaf-mode) skips too — its provider comes from
# var.cluster_groups[group.parent_group_name].dns_provider_id.
# `external` skips entirely — no provider row by definition.
data "ravion_dns_provider" "groups" {
  for_each = {
    for g in var.cert_groups : g.name => g
    if g.kind == "customer"
  }

  id = coalesce(each.value.dns_provider_id, "") != "" ? each.value.dns_provider_id : null
  given_id = (
    coalesce(each.value.dns_provider_id, "") == ""
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
