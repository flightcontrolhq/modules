output "domain_fqdns" {
  description = "Map of `<group>/<slug>` → resolved FQDN across every cert group + kind."
  value = merge(
    { for k, alloc in ravion_domain.ravion_auto_label : k => alloc.fqdn },
    { for name, alloc in ravion_domain.ravion_auto_auto : "${name}/auto" => alloc.fqdn },
    { for k, alloc in ravion_domain.customer : k => alloc.fqdn },
  )
}

output "domain_allocation_ids" {
  description = "Map of `<group>/<slug>` → DomainAllocation id."
  value = merge(
    { for k, alloc in ravion_domain.ravion_auto_label : k => alloc.id },
    { for name, alloc in ravion_domain.ravion_auto_auto : "${name}/auto" => alloc.id },
    { for k, alloc in ravion_domain.customer : k => alloc.id },
  )
}

output "customer_cert_arns" {
  description = "Map of group name → ACM cert ARN for customer-kind groups."
  value       = { for k, v in aws_acm_certificate_validation.customer : k => v.certificate_arn }
}
