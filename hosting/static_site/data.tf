data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Bucket policy granting CloudFront (via OAC) read access to the hosting bucket.
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
}

# Deploy role policy: sync to the hosting bucket, update the KVS active pointer,
# and (optionally) create CloudFront invalidations.
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
    sid    = "KvsDescribe"
    effect = "Allow"
    actions = [
      "cloudfront-keyvaluestore:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:ListKeys",
      "cloudfront-keyvaluestore:GetKey"
    ]
    resources = [aws_cloudfront_key_value_store.this.arn]
  }

  statement {
    sid    = "KvsWrite"
    effect = "Allow"
    actions = [
      "cloudfront-keyvaluestore:PutKey",
      "cloudfront-keyvaluestore:DeleteKey",
      "cloudfront-keyvaluestore:UpdateKeys"
    ]
    resources = [aws_cloudfront_key_value_store.this.arn]
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
