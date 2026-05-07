locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/eips"
  }

  tags = merge(local.default_tags, var.tags)
}
