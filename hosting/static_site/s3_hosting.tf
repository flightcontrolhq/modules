################################################################################
# Hosting Bucket
#
# Composes storage/s3 with a private bucket plus an OAC-style bucket policy that
# grants the CloudFront service principal read-only access (scoped to the
# distributions created by this module).
#
# Note: the policy document references module.cdn outputs, but
# aws_s3_bucket_policy is created separately from aws_s3_bucket inside
# storage/s3, so there is no cycle. The policy is rendered after the
# distributions exist.
################################################################################

module "hosting" {
  source = "../../storage/s3"
  count  = local.use_existing_bucket ? 0 : 1

  name               = var.name
  region             = var.region
  force_destroy      = var.bucket_force_destroy
  versioning_enabled = var.bucket_versioning
  kms_key_id         = var.kms_key_arn
  lifecycle_rules    = var.bucket_lifecycle_rules

  custom_policy        = data.aws_iam_policy_document.hosting_bucket_policy.json
  create_bucket_policy = true

  tags = local.tags
}

# When using a caller-supplied bucket (`existing_bucket_*` set), the
# bucket lives in another stack and that stack doesn't know our
# distribution ARNs. We still need the OAC grant for CloudFront, so
# attach the same policy here directly. The owning stack must NOT manage
# `aws_s3_bucket_policy` on this bucket — only one policy may exist per
# bucket at a time.
resource "aws_s3_bucket_policy" "existing" {
  count = local.use_existing_bucket ? 1 : 0

  bucket = var.existing_bucket_id
  policy = data.aws_iam_policy_document.hosting_bucket_policy.json
}
