data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Bucket policy granting CloudFront (via OAC) read access to the hosting bucket,
# and granting the Lambda@Edge role read access in filesystem_previews mode so
# the handler can perform headObject / getObject lookups directly against S3.
data "aws_iam_policy_document" "hosting_bucket_policy" {
  statement {
    sid       = local.oac_policy_sid
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.hosting_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [for k, v in module.cdn.distribution_arns : v]
    }
  }

  dynamic "statement" {
    for_each = local.uses_lambda_edge ? [1] : []
    content {
      sid    = local.edge_policy_sid
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      resources = [
        local.hosting_bucket_arn,
        "${local.hosting_bucket_arn}/*"
      ]

      principals {
        type        = "AWS"
        identifiers = [module.edge_lambda[0].role_arn]
      }
    }
  }
}

# Inline least-privilege S3 policy attached to the Lambda@Edge execution role.
data "aws_iam_policy_document" "lambda_edge_s3_read" {
  count = local.uses_lambda_edge ? 1 : 0

  statement {
    sid    = "ReadHostingBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      local.hosting_bucket_arn,
      "${local.hosting_bucket_arn}/*"
    ]
  }
}

# Deploy role policy: sync to the hosting bucket and create CloudFront invalidations.
data "aws_iam_policy_document" "deploy_role_policy" {
  count = var.create_deploy_role ? 1 : 0

  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.hosting_bucket_arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectAcl",
      "s3:AbortMultipartUpload"
    ]
    resources = ["${local.hosting_bucket_arn}/*"]
  }

  statement {
    sid    = "Invalidate"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
      "cloudfront:GetDistribution"
    ]
    resources = [for k, v in module.cdn.distribution_arns : v]
  }
}
