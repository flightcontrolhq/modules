################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_elb_service_account" "current" {}

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
  create_http_listener  = var.enable_http_listener
  create_https_listener = var.enable_https_listener
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Security group for ${var.name} ALB"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress_http" {
  count = local.create_http_listener ? 1 : 0

  type              = "ingress"
  from_port         = var.http_listener_port
  to_port           = var.http_listener_port
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidr_blocks
  ipv6_cidr_blocks  = var.ingress_ipv6_cidr_blocks
  security_group_id = aws_security_group.this.id
  description       = "Allow HTTP traffic"
}

resource "aws_security_group_rule" "ingress_https" {
  count = local.create_https_listener ? 1 : 0

  type              = "ingress"
  from_port         = var.https_listener_port
  to_port           = var.https_listener_port
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidr_blocks
  ipv6_cidr_blocks  = var.ingress_ipv6_cidr_blocks
  security_group_id = aws_security_group.this.id
  description       = "Allow HTTPS traffic"
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
}

################################################################################
# Application Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this.id]
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

################################################################################
# HTTP Listener
################################################################################

resource "aws_lb_listener" "http" {
  count = local.create_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.http_listener_port
  protocol          = "HTTP"

  # If HTTPS is enabled and redirect is enabled, redirect to HTTPS
  # Otherwise, return a fixed response
  dynamic "default_action" {
    for_each = var.http_to_https_redirect && local.create_https_listener ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = tostring(var.https_listener_port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = !var.http_to_https_redirect || !local.create_https_listener ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = var.default_action_content_type
        message_body = var.default_action_message
        status_code  = tostring(var.default_action_status_code)
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-http"
  })
}

################################################################################
# HTTPS Listener
################################################################################

resource "aws_lb_listener" "https" {
  count = local.create_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.https_listener_port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = var.default_action_content_type
      message_body = var.default_action_message
      status_code  = tostring(var.default_action_status_code)
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-https"
  })
}

################################################################################
# Additional Certificates (SNI)
################################################################################

resource "aws_lb_listener_certificate" "additional" {
  for_each = local.create_https_listener ? toset(var.additional_certificate_arns) : toset([])

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

################################################################################
# Access Logs - S3 Bucket
################################################################################

resource "aws_s3_bucket" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = "${var.name}-alb-access-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"

  tags = merge(local.tags, {
    Name = "${var.name}-alb-access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "access-logs-retention"
    status = "Enabled"

    expiration {
      days = var.access_logs_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowELBRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.current.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs[0].arn}/${var.access_logs_prefix != "" ? "${var.access_logs_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid    = "AllowELBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs[0].arn}/${var.access_logs_prefix != "" ? "${var.access_logs_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowELBLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.access_logs[0].arn
      }
    ]
  })
}

################################################################################
# WAF Association
################################################################################

resource "aws_wafv2_web_acl_association" "this" {
  count = var.web_acl_arn != null ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl_arn
}
