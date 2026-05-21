output "domain_fqdns" {
  description = "Map of `<group>/<slug>` → resolved FQDN across every cert group + kind."
  value = merge(
    { for k, alloc in ravion_domain.cluster_wildcard_label : k => alloc.fqdn },
    { for name, alloc in ravion_domain.cluster_wildcard_auto : "${name}/auto" => alloc.fqdn },
    { for k, alloc in ravion_domain.customer : k => alloc.fqdn },
  )
}

output "domain_allocation_ids" {
  description = "Map of `<group>/<slug>` → DomainAllocation id."
  value = merge(
    { for k, alloc in ravion_domain.cluster_wildcard_label : k => alloc.id },
    { for name, alloc in ravion_domain.cluster_wildcard_auto : "${name}/auto" => alloc.id },
    { for k, alloc in ravion_domain.customer : k => alloc.id },
  )
}

output "customer_cert_arns" {
  description = "Map of group name → ACM cert ARN for customer-kind groups."
  value       = { for k, v in aws_acm_certificate_validation.customer : k => v.certificate_arn }
}

output "cloudflare_api_token" {
  description = "First non-null Cloudflare api_token found among per-group providers. Used by parent modules to configure the cloudflare provider block. Null when no group resolves to a Cloudflare DnsProvider."
  value = try(
    [for _name, p in data.ravion_dns_provider.groups : p.cloudflare.api_token if p.cloudflare != null][0],
    null,
  )
  sensitive = true
}

output "parent_groups" {
  description = "Parent-mode output: map of group name → wildcard parent allocation + cert. Empty when mode = leaf. Service modules' cluster_wildcard kind looks up entries here via cluster_group_name."
  value = {
    for name, alloc in local.parent_allocations : name => {
      parent_allocation_id = alloc.id
      managed_domain_id    = alloc.managed_domain_id
      wildcard_fqdn        = alloc.fqdn
      cert_arn             = aws_acm_certificate_validation.parent[name].certificate_arn
      dns_provider_id      = alloc.provider.id
    }
  }
}
