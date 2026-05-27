################################################################################
# Ravion-managed domains for the static site (opt-in)
################################################################################
# When use_ravion_managed_domains = true, Ravion owns the CloudFront viewer
# certificate + aliases server-side (attached via target_arn = the distribution
# ARN). The cert MUST live in us-east-1 (CloudFront requirement).
#
#   domains = []      -> an auto-FQDN <name>-<hash>.<ravion-apex> (instance cert).
#   domains = [...]   -> a per-site cert over those FQDNs + CUSTOMER routing
#                        records the user adds (ALIAS to the distribution domain).
#
# IMPORTANT: in Ravion mode, configure var.distributions WITHOUT aliases/ACM
# cert so the cdn submodule leaves the default CloudFront cert in place; Ravion
# swaps the viewer cert + sets aliases via UpdateDistribution. See OPEN_QUESTIONS
# (B-static) for the cdn-submodule ignore_changes follow-up that makes this
# drift-free across applies.

locals {
  ravion_static_enabled      = var.use_ravion_managed_domains
  ravion_distribution_arn    = local.ravion_static_enabled ? try(values(module.cdn.distribution_arns)[0], null) : null
  ravion_distribution_domain = local.ravion_static_enabled ? try(values(module.cdn.distribution_domain_names)[0], null) : null
}

resource "ravion_certificate" "site" {
  count = local.ravion_static_enabled ? 1 : 0

  role           = "instance"
  domains        = length(var.domains) > 0 ? var.domains : null
  name           = length(var.domains) == 0 ? var.name : null
  aws_account_id = var.ravion_aws_account_id
  aws_region     = "us-east-1"
  target_arn     = local.ravion_distribution_arn

  lifecycle {
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id (aws_*) is required when use_ravion_managed_domains = true."
    }
    precondition {
      condition     = length(var.domains) <= 10
      error_message = "A static site may declare at most 10 custom domains."
    }
  }
}

# CUSTOMER routing records (one per custom FQDN): ALIAS to the distribution.
resource "ravion_domain" "custom" {
  for_each = local.ravion_static_enabled ? toset(var.domains) : toset([])

  name            = each.value
  target_dns_name = local.ravion_distribution_domain
  target_zone_id  = "Z2FDTNDATAQYW2" # CloudFront's global hosted zone id
}
