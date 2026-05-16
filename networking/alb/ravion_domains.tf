################################################################################
# Ravion-managed domains (opt-in)
################################################################################
# Single resource that drives the whole plug-and-play HTTPS dance:
#   1. allocates `<slot>-<random>.<platform-apex>` and pins it to this ALB
#      via an A-ALIAS record in Ravion's Route53 zone
#   2. issues the cluster wildcard ACM cert in `ravion_aws_account_id`
#   3. exposes `default_cert_arn` for the HTTPS listener's default cert
#
# The cert is attached to the listener as the LISTENER default. Per-service
# custom-domain certs (issued via `domains_module_certificate` elsewhere) are
# attached as additional SNI certs by api-go's reconciler, NOT by Terraform —
# so apply never blocks on customer DNS validation.

resource "domains_alb_attachment" "this" {
  count = var.use_ravion_managed_domains ? 1 : 0

  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)
  alb_dns_name   = aws_lb.this.dns_name
  alb_zone_id    = aws_lb.this.zone_id
  slot           = var.ravion_slot
  custom_domains = var.ravion_custom_domains
}
