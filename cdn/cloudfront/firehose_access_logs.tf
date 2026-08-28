################################################################################
# CloudFront Access Logs -> Amazon Data Firehose (standard logging v2)
################################################################################

locals {
  firehose_logging_enabled       = contains(local.logging_destinations, "firehose")
  firehose_logging_distributions = local.firehose_logging_enabled ? var.distributions : {}
  firehose_stream_name           = "${substr(var.name, 0, 43)}-cf-firehose-${substr(md5(var.name), 0, 8)}"
  firehose_role_name             = "${substr(var.name, 0, 38)}-cf-firehose-role-${substr(md5(var.name), 0, 8)}"
}

resource "aws_s3_bucket" "firehose_backup" {
  count = local.firehose_logging_enabled ? 1 : 0

  region = "us-east-1"

  bucket = "${substr(var.name, 0, 19)}-cf-firehose-${data.aws_caller_identity.current.account_id}-us-east-1-${substr(md5(var.name), 0, 8)}"
  tags   = merge(local.tags, { Name = "${var.name}-cf-firehose" })
}

resource "aws_s3_bucket_ownership_controls" "firehose_backup" {
  count = local.firehose_logging_enabled ? 1 : 0

  region = "us-east-1"
  bucket = aws_s3_bucket.firehose_backup[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  count = local.firehose_logging_enabled ? 1 : 0

  region = "us-east-1"
  bucket = aws_s3_bucket.firehose_backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_backup" {
  count = local.firehose_logging_enabled ? 1 : 0

  region = "us-east-1"
  bucket = aws_s3_bucket.firehose_backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "firehose_backup" {
  count = local.firehose_logging_enabled ? 1 : 0

  region = "us-east-1"
  bucket = aws_s3_bucket.firehose_backup[0].id

  rule {
    id     = "log-retention"
    status = "Enabled"

    expiration {
      days = var.logging_bucket_retention_days
    }
  }
}

data "aws_iam_policy_document" "firehose_assume_role" {
  count = local.firehose_logging_enabled ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "firehose" {
  count = local.firehose_logging_enabled ? 1 : 0

  name               = local.firehose_role_name
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role[0].json
  description        = "Allows CloudFront Firehose access logs to write failed deliveries and read endpoint credentials."
  tags               = local.tags
}

data "aws_iam_policy_document" "firehose" {
  count = local.firehose_logging_enabled ? 1 : 0

  statement {
    sid    = "WriteFailedDeliveries"
    effect = "Allow"

    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.firehose_backup[0].arn]
  }

  statement {
    sid    = "WriteFailedDeliveryObjects"
    effect = "Allow"

    actions   = ["s3:AbortMultipartUpload", "s3:PutObject"]
    resources = ["${aws_s3_bucket.firehose_backup[0].arn}/*"]
  }

  dynamic "statement" {
    for_each = var.logging_firehose_access_key_secret_arn != null ? [1] : []

    content {
      sid    = "ReadEndpointSecret"
      effect = "Allow"

      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.logging_firehose_access_key_secret_arn]
    }
  }

  dynamic "statement" {
    for_each = var.logging_firehose_access_key_secret_kms_key_arn != null ? [1] : []

    content {
      sid       = "DecryptEndpointSecret"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.logging_firehose_access_key_secret_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "firehose" {
  count = local.firehose_logging_enabled ? 1 : 0

  name   = "${local.firehose_role_name}-policy"
  role   = aws_iam_role.firehose[0].id
  policy = data.aws_iam_policy_document.firehose[0].json
}

resource "aws_kinesis_firehose_delivery_stream" "access_logs" {
  count = local.firehose_logging_enabled ? 1 : 0

  region      = "us-east-1"
  name        = local.firehose_stream_name
  destination = "http_endpoint"

  http_endpoint_configuration {
    url            = var.logging_firehose_endpoint_url
    name           = var.logging_firehose_endpoint_name
    role_arn       = aws_iam_role.firehose[0].arn
    retry_duration = 300
    s3_backup_mode = "FailedDataOnly"

    s3_configuration {
      role_arn           = aws_iam_role.firehose[0].arn
      bucket_arn         = aws_s3_bucket.firehose_backup[0].arn
      compression_format = "GZIP"
    }

    request_configuration {
      content_encoding = "GZIP"
    }

    dynamic "secrets_manager_configuration" {
      for_each = var.logging_firehose_access_key_secret_arn != null ? [1] : []

      content {
        enabled    = true
        role_arn   = aws_iam_role.firehose[0].arn
        secret_arn = var.logging_firehose_access_key_secret_arn
      }
    }

    access_key = var.logging_firehose_access_key
  }

  tags = merge(local.tags, { LogDeliveryEnabled = "true" })
}

resource "aws_cloudwatch_log_delivery_destination" "firehose_access_logs" {
  count = local.firehose_logging_enabled ? 1 : 0

  region = "us-east-1"

  name          = substr(replace("${var.name}-access-logs-firehose", "/[^a-zA-Z0-9-_.]/", "-"), 0, 60)
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_kinesis_firehose_delivery_stream.access_logs[0].arn
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_delivery" "firehose_access_logs" {
  for_each = local.firehose_logging_distributions

  region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.access_logs[each.key].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.firehose_access_logs[0].arn
  record_fields            = var.logging_firehose_record_fields

  tags = local.tags
}
