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

# Resolve the cluster's DnsProvider:
#
#   - Auto-mode (use_ravion_subdomain = true): look up the
#     platform-managed apex by its stable givenId. The api-go boot
#     seeds this row with `givenId = "ravion-platform-apex"` so any
#     Ravion deployment can reference it without knowing the opaque
#     dnsprov_* id.
#
#   - Customer mode (use_ravion_subdomain = false + caller-supplied
#     ravion_dns_provider_id / given_id): standard dual-lookup, same
#     as the V2 service modules.
#
# count = 0 path is the BYO-cert escape hatch (no provider configured;
# var.public_alb_certificate_arns is consumed directly).
data "ravion_dns_provider" "this" {
  count = local.enable_dns_provider_lookup ? 1 : 0
  id    = local.auto_provider_id
  given_id = (
    local.auto_provider_id == null
    ? local.auto_provider_given_id
    : null
  )
}
