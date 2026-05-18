################################################################################
# Ravion-managed cluster domain (opt-in)
################################################################################
# When var.use_ravion_managed_domains is true, this module allocates one
# `ravion_domain` for the cluster:
#
#   - Root domain (no parent) named `var.ravion_cluster_name` — falls back
#     to `var.name`.
#   - Target = public ALB (so the cluster apex itself resolves to the ALB
#     and any child service that doesn't have its own host_header rule
#     falls through to the ALB's default action).
#   - Wildcard cert covering `*.<cluster-fqdn>` + `<cluster-fqdn>` — every
#     `ecs_service` instance allocates a child under this domain and rides
#     this cert via SNI, so adding services costs zero ACM work.
#   - Optional `custom_domains` — SAN-added to the same cert so the
#     customer can also serve traffic via their own FQDNs. See the README
#     for the validation flow.
#
# The wildcard cert is attached as an SNI extra on the cluster ALB's HTTPS
# listener (NOT the default cert — the listener's default cert is set by
# `var.public_alb_certificate_arns` so existing customers aren't disturbed).
#
# Pass the outputs to each `ecs_service` instance:
#
#   module "service" {
#     source                     = ".../compute/ecs_service"
#     cluster_parent_domain_id   = module.cluster.ravion_cluster_domain_id
#     cluster_https_listener_arn = module.cluster.public_alb_https_listener_arn
#   }

resource "ravion_domain" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  name = coalesce(var.ravion_cluster_name, var.name)

  target = {
    dns_name = module.public_alb[0].alb_dns_name
    zone_id  = module.public_alb[0].alb_zone_id
  }

  certificate = {
    aws_account_id = var.ravion_aws_account_id
    aws_region     = coalesce(var.ravion_aws_region, local.region)
    wildcard       = true
    # Custom domains live on per-service modules now — each service
    # declares them via ecs_service's `domains` input. Cluster cert
    # covers only the wildcard pair.
  }

  lifecycle {
    precondition {
      condition     = !var.use_ravion_managed_domains || var.enable_public_alb
      error_message = "use_ravion_managed_domains requires enable_public_alb = true (the cluster domain's DNS target is the public ALB)."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id is required when use_ravion_managed_domains = true (the Ravion AwsAccount row id the wildcard cert is issued in, e.g. 'aws_abc123')."
    }
  }
}

# Attach the wildcard cert as an SNI extra on the cluster ALB's HTTPS
# listener. We do NOT replace the listener's default cert — that's still
# governed by var.public_alb_certificate_arns so opting in is safe for
# clusters that already have a default cert.
resource "aws_lb_listener_certificate" "ravion_cluster" {
  count = local.enable_ravion_domain && var.public_alb_enable_https ? 1 : 0

  listener_arn    = module.public_alb[0].https_listener_arn
  certificate_arn = ravion_domain.cluster[0].cert_arn
}
