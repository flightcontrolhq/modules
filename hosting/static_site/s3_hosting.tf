################################################################################
# Hosting Bucket
#
# Composes storage/s3 with a private bucket plus an OAC-style bucket policy that
# grants the CloudFront service principal read-only access (scoped to the
# distributions created by this module). In filesystem_previews mode, the
# Lambda@Edge execution role also gets read access for direct S3 lookups.
#
# Note: the policy_document references module.cdn outputs, but
# aws_s3_bucket_policy is created separately from aws_s3_bucket inside
# storage/s3, so there is no cycle. The policy is rendered after the
# distributions exist.
################################################################################

module "hosting" {
  source = "../../storage/s3"

  name               = var.name
  force_destroy      = var.bucket_force_destroy
  versioning_enabled = var.bucket_versioning
  kms_key_id         = var.kms_key_arn
  lifecycle_rules    = var.bucket_lifecycle_rules

  custom_policy        = data.aws_iam_policy_document.hosting_bucket_policy.json
  create_bucket_policy = true

  tags = local.tags
}
