################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/components"
  }

  tags = merge(local.default_tags, var.tags)
}
