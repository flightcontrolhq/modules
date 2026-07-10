data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Bucket policy granting CloudFront (via OAC) read access to the hosting bucket.
#
# s3:ListBucket is deliberately included alongside s3:GetObject: without it,
# S3 answers requests for missing keys with 403 AccessDenied (it can't reveal
# whether the key exists), and viewers get 403s for what are really 404s.
# With ListBucket, missing keys return proper 404s — and a genuine 403 can
# only mean the request was blocked (e.g. WAF), never "file missing".
#
# Why there is no s3:prefix condition: S3's implicit 404-vs-403 check on a
# missing GetObject evaluates ListBucket WITHOUT s3:prefix in the request
# context, so any prefix condition fails closed and reintroduces 403s —
# defeating the purpose. (CDK's AccessLevel.LIST grants the same
# unconditioned permission for the same reason.)
#
# Listing exposure instead relies on two guarantees that hold even if the
# viewer-request rewrite function is disabled, bypassed, or errors:
#   1. default_root_object rewrites "/" at the distribution level — before
#      any function runs — so a bare bucket GET (the only request shape that
#      returns a listing) never reaches S3.
#   2. The origin request policy (CORS-S3Origin by default) forwards no
#      query strings, so ListObjects parameters (prefix, list-type, ...)
#      can never reach S3 on any path.
# Every other URI maps to a GetObject, which this policy scopes to object
# ARNs. Keep both guarantees in place if you customize the distribution.
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

  statement {
    sid       = "AllowCloudFrontServicePrincipalList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.hosting_bucket_arn]

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
  count = var.deploy_role_creation_enabled ? 1 : 0

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
