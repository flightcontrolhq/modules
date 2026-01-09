################################################################################
# Application Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [module.security_group.security_group_id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout
  enable_http2               = var.enable_http2
  drop_invalid_header_fields = var.drop_invalid_header_fields
  desync_mitigation_mode     = var.desync_mitigation_mode
  preserve_host_header       = var.preserve_host_header
  xff_header_processing_mode = var.xff_header_processing_mode
  enable_waf_fail_open       = var.enable_waf_fail_open

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = local.access_logs_bucket_name
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  depends_on = [
    aws_s3_bucket_policy.access_logs
  ]

  lifecycle {
    precondition {
      condition     = !var.enable_https_listener || var.certificate_arn != null
      error_message = "A certificate_arn is required when enable_https_listener is true."
    }
  }
}

