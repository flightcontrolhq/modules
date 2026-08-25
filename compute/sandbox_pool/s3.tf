################################################################################
# Snapshot chunk store
#
# The only durable tier: host NVMe is a disposable cache of this bucket, which
# is what lets hosts be cattle. Holds the content-addressed chunk cache and the
# per-sandbox pause deltas.
################################################################################

resource "aws_s3_bucket" "snapshots" {
  bucket        = local.snapshots_bucket
  force_destroy = var.force_destroy_snapshots_bucket

  tags = merge(local.tags, { Name = local.snapshots_bucket })
}

resource "aws_s3_bucket_public_access_block" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Chunks are content-addressed: the same key always means the same bytes, so a
# version history could only ever hold duplicates.
resource "aws_s3_bucket_versioning" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  # S3 lifecycle filters can only match tags, never negate them, so the
  # exemption is expressed the other way round: the host tags every ordinary
  # object `ravion:pinned=false` and that is what expires. Prewarm bases and
  # fork parents are written with `ravion:pinned=true` (or no tag at all) and
  # no rule ever selects them.
  rule {
    id     = "expire-unpinned-snapshots"
    status = "Enabled"

    filter {
      tag {
        key   = "ravion:pinned"
        value = "false"
      }
    }

    expiration {
      days = var.snapshot_retention_days
    }
  }

  rule {
    id     = "abort-stuck-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }

  depends_on = [aws_s3_bucket_versioning.snapshots]
}

# The host role and, optionally, the Ravion cross-account role. Nobody else is
# granted anything, and public access is blocked above; the explicit deny below
# only closes the plaintext-transport hole.
resource "aws_s3_bucket_policy" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "HostRoleAccess"
        Effect    = "Allow"
        Principal = { AWS = compact([aws_iam_role.host.arn, var.ravion_role_arn]) }
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.snapshots.arn,
          "${aws_s3_bucket.snapshots.arn}/*",
        ]
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.snapshots.arn,
          "${aws_s3_bucket.snapshots.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.snapshots]
}
