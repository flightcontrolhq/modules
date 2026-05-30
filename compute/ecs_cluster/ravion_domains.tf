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
  enable_ravion_domain = var.use_ravion_managed_domains && (var.enable_public_alb || var.enable_private_alb)
}

# Plan-time guard against two clusters claiming the same wildcard apex. The
# backend resolves the bare name leaf to the managed wildcard (*.<name>.<apex>)
# and reports collides=true ONLY when a DIFFERENT module instance already owns
# that domain — a re-apply of THIS cluster does not collide with itself. The
# allocator enforces the same rule server-side as an apply-time backstop.
data "ravion_dns_collision_check" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0
  fqdn  = coalesce(var.ravion_cluster_name, var.module_instance_given_id, var.name)
}

resource "ravion_certificate" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  role           = "shared_wildcard"
  wildcard       = true
  name           = coalesce(var.ravion_cluster_name, var.module_instance_given_id, var.name)
  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)

  # Ravion publishes a *.<apex> ALIAS to this ALB so service auto-FQDNs
  # (<svc>.<apex>) resolve under the cluster wildcard. Public ALB if present,
  # else private. (A single wildcard record serves one ALB; mixed public+private
  # clusters route to the public one.)
  target_dns_name = var.enable_public_alb ? module.public_alb[0].alb_dns_name : (var.enable_private_alb ? module.private_alb[0].alb_dns_name : null)
  target_zone_id  = var.enable_public_alb ? module.public_alb[0].alb_zone_id : (var.enable_private_alb ? module.private_alb[0].alb_zone_id : null)

  lifecycle {
    # Rotating the cluster wildcard cert (any RequiresReplace change, e.g. a
    # renamed apex) must issue the new cert and swap it onto the HTTPS
    # listener(s) BEFORE the old one is torn down. Without this, terraform
    # destroys the old cert first while it is still the listener's default —
    # ACM returns ResourceInUse and the rotation deadlocks. create_before_destroy
    # makes it new -> listener in-place swap -> delete old (now detached).
    create_before_destroy = true

    precondition {
      condition     = !var.use_ravion_managed_domains || var.enable_public_alb || var.enable_private_alb
      error_message = "use_ravion_managed_domains requires at least one ALB (enable_public_alb or enable_private_alb)."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id (aws_*) is required when use_ravion_managed_domains = true."
    }
    precondition {
      condition     = !coalesce(one(data.ravion_dns_collision_check.cluster[*].collides), false)
      error_message = "Cluster wildcard apex is already claimed by another cluster: a managed *.<ravion_cluster_name>.<apex> domain owned by a different module instance already exists. Pick a unique ravion_cluster_name."
    }
  }
}
