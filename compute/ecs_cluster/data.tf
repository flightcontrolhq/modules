################################################################################
# Data Sources
################################################################################

# Get the latest ECS-optimized Amazon Linux 2023 AMI
data "aws_ssm_parameter" "ecs_optimized_ami" {
  count = local.enable_ec2 && var.ec2_ami_id == null ? 1 : 0

  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Resolve the registered Ravion DnsProvider that the cluster's
# wildcard FQDN + cert hang off. Accepts an opaque id
# (`ravion_dns_provider_id = "dnsprov_..."`) OR a per-org stable
# `given_id` — the api-go handler does a dual lookup. Exactly one of
# the per-variant attribute groups (`route53_ravion`, `route53`,
# `cloudflare`, `external`) is non-null on the returned row; the count
# gating in ravion_domains.tf dispatches on those.
#
# The count = 0 branch (no provider configured) is the BYO-cert path —
# `var.public_alb_certificate_arns` is consumed directly.
data "ravion_dns_provider" "this" {
  count    = local.dns_provider_lookup_key == "" ? 0 : 1
  id       = var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != "" ? var.ravion_dns_provider_id : null
  given_id = var.ravion_dns_provider_given_id != null && var.ravion_dns_provider_given_id != "" ? var.ravion_dns_provider_given_id : null
}
