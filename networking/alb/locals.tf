locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/alb"
  }
  tags = merge(local.default_tags, var.tags)

  # Access Logs
  create_access_logs_bucket = var.enable_access_logs && var.access_logs_bucket_arn == null
  access_logs_bucket_name = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : (
    var.access_logs_bucket_arn != null ? regex("arn:aws:s3:::(.+)", var.access_logs_bucket_arn)[0] : null
  )

  # Listener configuration
  create_http_listener = var.enable_http_listener
  # HTTPS listener is created when either the user opts in explicitly OR
  # Ravion-managed domains are enabled (always implies HTTPS).
  create_https_listener = var.enable_https_listener || var.use_ravion_managed_domains

  # Default cert for the HTTPS listener: Ravion-managed wins over the
  # user-supplied list. Additional SNI certs are attached out-of-band by
  # api-go's reconciler (NOT here) — keeps apply from blocking on customer DNS.
  https_default_cert_arn = (
    var.use_ravion_managed_domains && length(domains_alb_attachment.this) > 0
    ? domains_alb_attachment.this[0].default_cert_arn
    : (length(var.certificate_arns) > 0 ? var.certificate_arns[0] : null)
  )
}



