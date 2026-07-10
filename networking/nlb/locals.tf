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
    Module    = "networking/nlb"
  }
  tags = merge(local.default_tags, var.tags)

  # Access Logs
  create_access_logs_bucket = var.access_logs_enabled && var.access_logs_bucket_arn == null
  access_logs_bucket_name = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : (
    var.access_logs_bucket_arn != null ? regex("arn:aws:s3:::(.+)", var.access_logs_bucket_arn)[0] : null
  )
}
