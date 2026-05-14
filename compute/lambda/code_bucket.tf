################################################################################
# Code Bucket (auto-created for Zip package_type when no source is provided)
################################################################################

module "code_bucket" {
  count = local.create_code_bucket ? 1 : 0

  source = "../../storage/s3"

  name               = local.code_bucket_name
  region             = var.region
  versioning_enabled = true
  force_destroy      = var.code_bucket_force_destroy
  tags               = local.tags
}

resource "aws_s3_object" "placeholder" {
  count = local.create_code_bucket ? 1 : 0

  bucket      = module.code_bucket[0].bucket_id
  key         = var.placeholder_object_key
  source      = data.archive_file.placeholder[0].output_path
  source_hash = data.archive_file.placeholder[0].output_base64sha256

  lifecycle {
    ignore_changes = [source, source_hash, etag]
  }
}
