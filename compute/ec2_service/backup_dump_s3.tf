################################################################################
# Logical dump S3 bucket
################################################################################

resource "aws_s3_bucket" "dump" {
  count = local.backup_dump_bucket_created ? 1 : 0

  bucket        = "${var.name}-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.backup_dump_force_deletion_enabled

  tags = merge(local.tags, {
    Name = "${var.name}-backups"
  })
}

resource "aws_s3_bucket_public_access_block" "dump" {
  count = local.backup_dump_bucket_created ? 1 : 0

  bucket = aws_s3_bucket.dump[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dump" {
  count = local.backup_dump_bucket_created ? 1 : 0

  bucket = aws_s3_bucket.dump[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "dump" {
  count = local.backup_dump_bucket_created ? 1 : 0

  bucket = aws_s3_bucket.dump[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "dump" {
  count = local.backup_dump_bucket_created ? 1 : 0

  bucket = aws_s3_bucket.dump[0].id

  rule {
    id     = "logical-dump-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_dump_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_dump_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "dump" {
  count = local.backup_dump_bucket_created ? 1 : 0

  bucket = aws_s3_bucket.dump[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.dump[0].arn,
        "${aws_s3_bucket.dump[0].arn}/*",
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}
