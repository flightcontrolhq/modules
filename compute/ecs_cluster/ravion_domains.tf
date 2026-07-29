################################################################################
# Ravion-managed cluster domain (opt-in)
################################################################################
# When var.use_ravion_managed_domains = true, Ravion issues ONE wildcard cert
# `*.<name>-<hash>.<ravion-apex>` (+ apex). That cert becomes the default cert
# on the cluster ALB HTTPS listener(s) (see listeners.tf) — a single ACM cert
# can default both the public and the private listener, so public AND private
# services nest their domains under the one wildcard. The cert also publishes a
# `*.<apex>` ALIAS to the cluster ALB so service auto-FQDNs (<svc>.<apex>)
# resolve. When the flag is off, this resource is absent and the listeners fall
# back to the customer-supplied certificate ARNs.

locals {
  enable_ravion_domain = var.use_ravion_managed_domains && (var.public_alb_enabled || var.private_alb_enabled)
}

# Plan-time guards (wildcard-apex collision against another cluster, and
# dependents on teardown) run automatically inside the provider's ModifyPlan —
# no data source + precondition wiring needed. The allocator enforces the same
# rules server-side as an apply-time backstop.
resource "ravion_aws_acm_certificate" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  wildcard           = true
  name               = coalesce(var.ravion_cluster_name, var.module_instance_given_id, var.name)
  module_instance_id = var.module_instance_id
  aws_account_id     = var.ravion_aws_account_id
  aws_region         = coalesce(var.ravion_aws_region, local.region)

  # Ravion publishes a *.<apex> ALIAS to this ALB so service auto-FQDNs
  # (<svc>.<apex>) resolve under the cluster wildcard. Public ALB if present,
  # else private. (A single wildcard record serves one ALB; mixed public+private
  # clusters route to the public one.)
  target_dns_name = var.public_alb_enabled ? module.public_alb[0].alb_dns_name : (var.private_alb_enabled ? module.private_alb[0].alb_dns_name : null)
  target_zone_id  = var.public_alb_enabled ? module.public_alb[0].alb_zone_id : (var.private_alb_enabled ? module.private_alb[0].alb_zone_id : null)

  lifecycle {
    # Rotating the cluster wildcard cert (any RequiresReplace change, e.g. a
    # renamed apex) must issue the new cert and swap it onto the HTTPS
    # listener(s) BEFORE the old one is torn down. Without this, terraform
    # destroys the old cert first while it is still the listener's default —
    # ACM returns ResourceInUse and the rotation deadlocks. create_before_destroy
    # makes it new -> listener in-place swap -> delete old (now detached).
    create_before_destroy = true

    precondition {
      condition     = !var.use_ravion_managed_domains || var.public_alb_enabled || var.private_alb_enabled
      error_message = "use_ravion_managed_domains requires at least one ALB (public_alb_enabled or private_alb_enabled)."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id (aws_*) is required when use_ravion_managed_domains = true."
    }
  }
}
