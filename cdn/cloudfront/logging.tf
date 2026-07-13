locals {
  s3_logging_enabled     = var.logging_enabled && var.logging_destination == "s3"
  logging_bucket_enabled = local.s3_logging_enabled && var.logging_bucket_creation_enabled
}

resource "aws_s3_bucket" "logging" {
  count = local.logging_bucket_enabled ? 1 : 0

  bucket = "${var.name}-cf-logs-${data.aws_caller_identity.current.account_id}-${local.region}"
  tags   = merge(local.tags, { Name = "${var.name}-cf-logs" })
}

resource "aws_s3_bucket_ownership_controls" "logging" {
  count = local.logging_bucket_enabled ? 1 : 0

  bucket = aws_s3_bucket.logging[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logging" {
  count = local.logging_bucket_enabled ? 1 : 0

  bucket     = aws_s3_bucket.logging[0].id
  acl        = "log-delivery-write"
  depends_on = [aws_s3_bucket_ownership_controls.logging]
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  count = local.logging_bucket_enabled ? 1 : 0

  bucket = aws_s3_bucket.logging[0].id

  rule {
    id     = "log-retention"
    status = "Enabled"

    expiration {
      days = var.logging_bucket_retention_days
    }
  }
}
