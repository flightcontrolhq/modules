locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "storage/efs"
  }
  tags = merge(local.default_tags, var.tags)

  create_access_point = var.access_point_enabled

  # creation_info is only valid for non-root directories. EFS creates the
  # directory with this ownership on first mount through the access point.
  access_point_creation_info_enabled = local.create_access_point && var.access_point_root_directory_path != "/"
}
