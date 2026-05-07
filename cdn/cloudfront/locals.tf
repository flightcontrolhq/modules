locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "cdn/cloudfront"
  }

  tags = merge(local.default_tags, var.tags)
}
