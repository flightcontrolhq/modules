################################################################################
# Ravion-managed service domain (opt-in)
################################################################################
# When var.cluster_parent_domain_id is set, this module always declares an
# auto-allocated FQDN child of the cluster (Mode A — rides the cluster
# wildcard via SNI). When var.domains is non-empty, it additionally
# declares a Mode B `ravion_domain` carrying its own cert that covers
# only the customer FQDNs.
#
# Both live side-by-side: the listener rule matches BOTH the auto-FQDN
# AND every customer FQDN. This gives the customer a no-downtime window
# to flip their DNS over — until then, traffic to the auto-FQDN keeps
# working. Once the customer's DNS records resolve (MATCHED in the
# Domains tab), the Ravion control plane retires the auto-FQDN
# (`MaybeRetireAutoDomain` deletes the Route53 record + soft-deletes
# the allocation). The listener rule keeps both entries — the orphaned
# auto-FQDN match is harmless because no DNS resolves to it anymore.
#
# Wire the parent ecs_cluster module's Ravion outputs:
#   module "service" {
#     source                     = ".../compute/ecs_service"
#     cluster_parent_domain_id   = module.cluster.ravion_cluster_domain_id
#     cluster_https_listener_arn = module.cluster.public_alb_https_listener_arn
#     cluster_alb_dns_name       = module.cluster.public_alb_dns_name   # Mode B only
#     cluster_alb_zone_id        = module.cluster.public_alb_zone_id    # Mode B only
#     ravion_aws_account_id      = module.cluster.ravion_aws_account_id # Mode B only
#     ravion_aws_region          = module.cluster.ravion_aws_region     # Mode B only
#     domains                    = ["api.example.com"]                  # opts into Mode B
#   }

locals {
  ravion_managed      = var.cluster_parent_domain_id != null && var.cluster_parent_domain_id != ""
  ravion_has_listener = var.cluster_https_listener_arn != null && var.cluster_https_listener_arn != ""
  ravion_mode_b       = local.ravion_managed && length(var.domains) > 0

  # Hash-derived priority slot in [1000, 49999]. All services in the
  # same cluster share one HTTPS listener, and AWS rejects rule
  # priority collisions. Deriving from `var.name` gives every service
  # a deterministic, unique slot without anyone hand-picking numbers.
  # `var.ravion_listener_rule_priority` overrides this when set
  # explicitly (sentinel default is 0).
  ravion_priority_auto = (parseint(substr(sha256(var.name), 0, 4), 16) % 49000) + 1000
  ravion_priority      = var.ravion_listener_rule_priority > 0 ? var.ravion_listener_rule_priority : local.ravion_priority_auto

  # Cutover signal from Ravion. Defaults to false (auto-FQDN stays) for
  # every state EXCEPT "allocation released AND at least one sibling
  # custom-domain routing record is MATCHED". Once it flips true, the
  # auto resource's count goes to 0 and TF plans a clean destroy on the
  # next apply.
  #
  # Honoured ONLY while there's a Mode B custom-domain successor. When
  # the user removes all custom domains (Mode B → Mode A), we IGNORE
  # retirement and re-create the auto-FQDN — otherwise the listener
  # rule below would have zero host_header values and AWS would reject
  # the apply.
  ravion_auto_retired = local.ravion_managed && local.ravion_mode_b ? try(data.ravion_auto_domain_status.auto[0].retired, false) : false

  # Listener rule matches the auto-FQDN (when not yet retired) plus
  # every customer FQDN. Two-step cutover at the TF layer:
  #   1) Add `domains` → host_header = [auto, customer]
  #   2) Customer DNS resolves → Ravion retires → host_header = [customer]
  ravion_host_header_values = concat(
    [for r in ravion_domain.auto : r.fqdn],
    local.ravion_mode_b ? var.domains : [],
  )

  ravion_target_group_arn = local.enable_load_balancer && var.deployment_type == "rolling" ? (
    length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : null
    ) : (
    length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
  )
}

# Read cutover status from Ravion every plan. Independent of the auto
# resource's own state — avoids the count-depends-on-self chicken-and-egg.
data "ravion_auto_domain_status" "auto" {
  count = local.ravion_managed ? 1 : 0

  parent_domain_id = var.cluster_parent_domain_id
  name             = var.name
}

# Mode A — allocated when the cluster domain is wired AND Ravion hasn't
# retired this slot. After cutover, count → 0 → TF destroys naturally.
resource "ravion_domain" "auto" {
  count = local.ravion_managed && !local.ravion_auto_retired ? 1 : 0

  name      = var.name
  parent_id = var.cluster_parent_domain_id
}

# Mode B — additional resource that issues a service cert covering only
# var.domains. Ravion handles the SNI attach to the cluster's HTTPS listener
# server-side via `resource_arn`: TF returns fast (cert REQUESTED), the
# bind lands once ACM validates the cert. No separate
# `aws_lb_listener_certificate` resource needed.
resource "ravion_domain" "custom" {
  count = local.ravion_mode_b ? 1 : 0

  name      = "${var.name}-custom"
  parent_id = var.cluster_parent_domain_id

  target = {
    dns_name = var.cluster_alb_dns_name
    zone_id  = var.cluster_alb_zone_id
  }

  certificate = {
    aws_account_id = var.ravion_aws_account_id
    aws_region     = coalesce(var.ravion_aws_region, local.region)
    domains        = var.domains
  }

  resource_arn = var.cluster_https_listener_arn

  lifecycle {
    precondition {
      condition     = var.cluster_alb_dns_name != null && var.cluster_alb_dns_name != "" && var.cluster_alb_zone_id != null && var.cluster_alb_zone_id != ""
      error_message = "Setting `domains` (Mode B) requires cluster_alb_dns_name + cluster_alb_zone_id (pipe module.cluster.public_alb_dns_name + module.cluster.public_alb_zone_id)."
    }
    precondition {
      condition     = var.ravion_aws_account_id != null && var.ravion_aws_account_id != ""
      error_message = "Setting `domains` (Mode B) requires ravion_aws_account_id (pipe module.cluster.ravion_aws_account_id)."
    }
    precondition {
      condition     = var.cluster_https_listener_arn != null && var.cluster_https_listener_arn != ""
      error_message = "Setting `domains` (Mode B) requires cluster_https_listener_arn so Ravion can attach the new cert to the ALB."
    }
  }
}

resource "aws_lb_listener_rule" "ravion" {
  # Defensive: never declare the listener rule when there are zero
  # host_header values — AWS ALB requires ≥ 1. Both `ravion_managed`
  # and `ravion_host_header_values` should be non-empty under normal
  # config flow; this guard catches transient TF states (e.g. the
  # auto-FQDN was retired AND custom domains haven't been added yet).
  count = local.ravion_managed && local.ravion_has_listener && length(local.ravion_host_header_values) > 0 ? 1 : 0

  listener_arn = var.cluster_https_listener_arn
  priority     = local.ravion_priority

  condition {
    host_header {
      values = local.ravion_host_header_values
    }
  }

  action {
    type             = "forward"
    target_group_arn = local.ravion_target_group_arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-ravion"
  })

  # Blue/green deploy controllers flip the rule's action to swap target groups
  # behind the scenes. Without this, every TF apply would reset the action back
  # to tg_1 and undo the swap. No-op for rolling deployments.
  lifecycle {
    ignore_changes = [action]
  }
}
