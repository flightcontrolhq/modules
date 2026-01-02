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
  create_access_logs_bucket = var.enable_access_logs && var.access_logs_bucket_arn == null
  access_logs_bucket_name = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : (
    var.access_logs_bucket_arn != null ? regex("arn:aws:s3:::(.+)", var.access_logs_bucket_arn)[0] : null
  )

  # TLS Listeners (for SNI certificate handling)
  tls_listeners = { for k, v in var.listeners : k => v if v.protocol == "TLS" }

  # Flatten additional certificates across all TLS listeners
  additional_certificates = flatten([
    for listener_key, listener in local.tls_listeners : [
      for cert_arn in listener.additional_certificate_arns : {
        listener_key    = listener_key
        certificate_arn = cert_arn
      }
    ]
  ])
}
