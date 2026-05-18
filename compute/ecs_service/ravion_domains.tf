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

################################################################################
# Per-service auto-domain (lives ON the cluster wildcard cert)
################################################################################
# Active only when:
#   - var.domains is empty (no custom-domain takeover yet), AND
#   - var.ravion_parent_app_domain_id is set (cluster has Ravion-managed
#     domains enabled and exposed its default app_domain id)
#
# Layout:
#   1. domains_app_domain.auto allocates `<svc>-<hash>.<cluster-fqdn>` —
#      because parent_id is the cluster's app_domain, the FQDN lives under
#      the cluster's auto-allocated apex, and the cluster wildcard cert
#      (`*.<cluster-fqdn>`) covers it as SNI with no per-service ACM work.
#   2. domains_dns_record.auto_alias writes the A-ALIAS in our Route53
#      pointing the auto-FQDN at the cluster ALB.
#   3. aws_lb_listener_rule.auto installs a host_header rule on the cluster's
#      HTTPS listener so requests to the auto-FQDN route to this service's
#      target group.
#
# When the user adds a custom domain (var.domains becomes non-empty), all
# three resources flip to count=0 and Terraform destroys them — the api
# soft-deletes the ManagedDomain row, removes the Route53 record, and AWS
# deletes the listener rule. The user's custom domain takes over via
# `domains_module_certificate.this` above.

locals {
  ravion_auto_domain_enabled = (
    length(var.domains) == 0
    && var.ravion_parent_app_domain_id != null
    && var.ravion_parent_app_domain_id != ""
  )
}

resource "domains_app_domain" "auto" {
  count = local.ravion_auto_domain_enabled ? 1 : 0

  slot      = "service-auto"
  parent_id = var.ravion_parent_app_domain_id
}

resource "domains_dns_record" "auto_alias" {
  count = local.ravion_auto_domain_enabled ? 1 : 0

  domain_id = domains_app_domain.auto[0].id
  name      = ""
  type      = "ALIAS"
  value = jsonencode({
    dns_name = var.ravion_auto_domain_alb_dns_name
    zone_id  = var.ravion_auto_domain_alb_zone_id
  })
}

resource "aws_lb_listener_rule" "ravion_auto_domain" {
  count = local.ravion_auto_domain_enabled ? 1 : 0

  listener_arn = var.ravion_auto_domain_listener_arn
  priority     = var.ravion_auto_domain_listener_rule_priority

  condition {
    host_header {
      values = [domains_app_domain.auto[0].domain]
    }
  }

  action {
    type             = "forward"
    target_group_arn = local.enable_load_balancer && var.deployment_type == "rolling" ? aws_lb_target_group.this[0].arn : aws_lb_target_group.tg_1[0].arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-ravion-auto"
  })
}
