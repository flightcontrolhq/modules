################################################################################
# Hosted Zone
################################################################################

output "zone_id" {
  description = "The ID of the Route53 hosted zone."
  value       = local.zone_id
}

output "zone_arn" {
  description = "The ARN of the Route53 hosted zone (null when referencing an existing zone)."
  value = (
    local.create_public_zone ? aws_route53_zone.public[0].arn :
    var.create_zone && var.private_zone ? aws_route53_zone.private[0].arn :
    null
  )
}

output "zone_name" {
  description = "The name of the Route53 hosted zone."
  value = (
    local.create_public_zone ? aws_route53_zone.public[0].name :
    var.create_zone && var.private_zone ? aws_route53_zone.private[0].name :
    data.aws_route53_zone.existing[0].name
  )
}

output "name_servers" {
  description = "The name servers assigned to the hosted zone (empty for private zones)."
  value = (
    local.create_public_zone ? aws_route53_zone.public[0].name_servers :
    var.create_zone && var.private_zone ? aws_route53_zone.private[0].name_servers :
    data.aws_route53_zone.existing[0].name_servers
  )
}

output "primary_name_server" {
  description = "The primary name server of the hosted zone."
  value = (
    local.create_public_zone ? aws_route53_zone.public[0].primary_name_server :
    var.create_zone && var.private_zone ? aws_route53_zone.private[0].primary_name_server :
    data.aws_route53_zone.existing[0].primary_name_server
  )
}

output "is_private_zone" {
  description = "Whether the hosted zone is a private zone."
  value       = var.create_zone ? var.private_zone : data.aws_route53_zone.existing[0].private_zone
}

################################################################################
# Records
################################################################################

output "record_names" {
  description = "A map of record keys to their fully qualified domain names."
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}

output "record_ids" {
  description = "A map of record keys to their Route53 record IDs."
  value       = { for k, r in aws_route53_record.this : k => r.id }
}

################################################################################
# DNSSEC
################################################################################

output "dnssec_key_signing_key_id" {
  description = "The ID of the DNSSEC key signing key (null when DNSSEC is disabled)."
  value       = var.enable_dnssec ? aws_route53_key_signing_key.this[0].id : null
}

output "dnssec_ds_record" {
  description = "The DS record value to publish in the parent zone (null when DNSSEC is disabled)."
  value       = var.enable_dnssec ? aws_route53_key_signing_key.this[0].ds_record : null
}

################################################################################
# Query Logging
################################################################################

output "query_log_id" {
  description = "The ID of the Route53 query log configuration (null when disabled)."
  value       = var.enable_query_logging ? aws_route53_query_log.this[0].id : null
}
