################################################################################
# Code Bucket (auto-created for Zip package_type when no source is provided)
################################################################################

module "code_bucket" {
  count = local.create_code_bucket ? 1 : 0

  source = "../../storage/s3"

  name                  = local.code_bucket_name
  region                = var.region
  versioning_enabled    = true
  force_destroy_enabled = var.code_bucket_force_destroy_enabled
  tags                  = local.tags
}

resource "aws_s3_object" "bootstrap_package" {
  count = local.create_code_bucket ? 1 : 0

  bucket         = module.code_bucket[0].bucket_id
  key            = var.placeholder_object_key
  content_base64 = local.bootstrap_package_zip_base64

  lifecycle {
    ignore_changes = [content_base64, etag]
  }
}

moved {
  from = aws_s3_object.placeholder
  to   = aws_s3_object.bootstrap_package
}
