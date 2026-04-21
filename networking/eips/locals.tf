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
