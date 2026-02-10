resource "aws_s3_bucket" "logging" {
  count = var.create_logging_bucket ? 1 : 0

  bucket = "${var.name}-cf-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"
  tags   = merge(local.tags, { Name = "${var.name}-cf-logs" })
}

resource "aws_s3_bucket_ownership_controls" "logging" {
  count = var.create_logging_bucket ? 1 : 0

  bucket = aws_s3_bucket.logging[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logging" {
  count = var.create_logging_bucket ? 1 : 0

  bucket     = aws_s3_bucket.logging[0].id
  acl        = "log-delivery-write"
  depends_on = [aws_s3_bucket_ownership_controls.logging]
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  count = var.create_logging_bucket ? 1 : 0

  bucket = aws_s3_bucket.logging[0].id

  rule {
    id     = "log-retention"
    status = "Enabled"

    expiration {
      days = var.logging_bucket_retention_days
    }
  }
}
