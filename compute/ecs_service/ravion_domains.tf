################################################################################
# Ravion-managed per-service custom domains (opt-in via var.domains)
################################################################################
# One cert covering every FQDN in var.domains. Lifecycle:
#   create -> api requests ACM cert, persists DNS validation CNAMEs in DB,
#             status PENDING_VALIDATION (visible in Domains tab)
#   read   -> mirrors current ACM status
#   update -> domains list is RequiresReplace (ACM doesn't allow SAN edits)
#   delete -> api detaches from listener, releases the ACM cert
#
# The cert is attached to var.ravion_listener_arn out-of-band by api-go's
# reconciler once it reaches ISSUED. terraform apply never blocks on
# customer DNS validation.

resource "domains_module_certificate" "this" {
  count = length(var.domains) > 0 ? 1 : 0

  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)
  domains        = var.domains
  listener_arn   = var.ravion_listener_arn
}
