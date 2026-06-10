################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_route53_zone" "existing" {
  count   = var.zone_enabled ? 0 : 1
  zone_id = var.zone_id
}
