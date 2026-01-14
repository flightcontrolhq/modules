################################################################################
# S3 Module Unit Tests
################################################################################

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_elb_service_account.current
    values = {
      arn = "arn:aws:iam::127311923021:root"
      id  = "127311923021"
    }
  }
}

#-------------------------------------------------------------------------------
# Name Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid bucket name - basic
run "test_name_validation_valid_basic" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = var.name == "my-test-bucket"
    error_message = "Valid bucket name should be accepted."
  }
}

# Test: Valid bucket name - with numbers
run "test_name_validation_valid_with_numbers" {
  command = plan

  variables {
    name = "bucket-123-test"
  }

  assert {
    condition     = var.name == "bucket-123-test"
    error_message = "Valid bucket name with numbers should be accepted."
  }
}

# Test: Valid bucket name - with periods
run "test_name_validation_valid_with_periods" {
  command = plan

  variables {
    name = "my.test.bucket"
  }

  assert {
    condition     = var.name == "my.test.bucket"
    error_message = "Valid bucket name with periods should be accepted."
  }
}

# Test: Valid bucket name - minimum length (3 characters)
run "test_name_validation_valid_min_length" {
  command = plan

  variables {
    name = "abc"
  }

  assert {
    condition     = length(var.name) == 3
    error_message = "Valid bucket name with minimum length (3 characters) should be accepted."
  }
}

# Test: Valid bucket name - starting with number
run "test_name_validation_valid_starts_with_number" {
  command = plan

  variables {
    name = "123-bucket"
  }

  assert {
    condition     = var.name == "123-bucket"
    error_message = "Valid bucket name starting with number should be accepted."
  }
}

# Test: Invalid bucket name - too short (less than 3 characters)
run "test_name_validation_min_length" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - too long (more than 63 characters)
run "test_name_validation_max_length" {
  command = plan

  variables {
    name = "this-bucket-name-is-way-too-long-and-exceeds-the-sixty-three-character-limit-set-by-aws"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - contains uppercase letters
run "test_name_validation_invalid_uppercase" {
  command = plan

  variables {
    name = "My-Test-Bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - contains underscores
run "test_name_validation_invalid_underscore" {
  command = plan

  variables {
    name = "my_test_bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - starts with hyphen
run "test_name_validation_hyphen_start" {
  command = plan

  variables {
    name = "-my-bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - ends with hyphen
run "test_name_validation_hyphen_end" {
  command = plan

  variables {
    name = "my-bucket-"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - starts with period
run "test_name_validation_period_start" {
  command = plan

  variables {
    name = ".my-bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - ends with period
run "test_name_validation_period_end" {
  command = plan

  variables {
    name = "my-bucket."
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - consecutive periods
run "test_name_validation_consecutive_periods" {
  command = plan

  variables {
    name = "my..bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - formatted as IP address
run "test_name_validation_ip_address" {
  command = plan

  variables {
    name = "192.168.1.1"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - contains special characters
run "test_name_validation_invalid_special_chars" {
  command = plan

  variables {
    name = "my@bucket!"
  }

  expect_failures = [
    var.name,
  ]
}

#-------------------------------------------------------------------------------
# Force Destroy Tests
#-------------------------------------------------------------------------------

# Test: force_destroy defaults to false
run "test_force_destroy_default_false" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = var.force_destroy == false
    error_message = "force_destroy should default to false."
  }
}

# Test: force_destroy can be set to true
run "test_force_destroy_can_be_true" {
  command = plan

  variables {
    name          = "test-bucket"
    force_destroy = true
  }

  assert {
    condition     = var.force_destroy == true
    error_message = "force_destroy should be able to be set to true."
  }
}

#-------------------------------------------------------------------------------
# Tags Tests
#-------------------------------------------------------------------------------

# Test: tags default to empty map
run "test_tags_default_empty" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(var.tags) == 0
    error_message = "tags should default to an empty map."
  }
}

# Test: tags can be provided
run "test_tags_can_be_provided" {
  command = plan

  variables {
    name = "test-bucket"
    tags = {
      Environment = "test"
      Project     = "s3-module"
    }
  }

  assert {
    condition     = var.tags["Environment"] == "test"
    error_message = "Custom tags should be accepted."
  }
}

#-------------------------------------------------------------------------------
# S3 Bucket Resource Tests
#-------------------------------------------------------------------------------

# Test: bucket is created with correct name
run "test_bucket_creation_with_name" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "my-test-bucket"
    error_message = "Bucket should be created with the specified name."
  }
}

# Test: bucket force_destroy defaults to false
run "test_bucket_force_destroy_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "Bucket force_destroy should default to false."
  }
}

# Test: bucket force_destroy can be set to true
run "test_bucket_force_destroy_true" {
  command = plan

  variables {
    name          = "test-bucket"
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "Bucket force_destroy should be set to true when specified."
  }
}

# Test: bucket has default tags merged
run "test_bucket_default_tags" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["ManagedBy"] == "terraform"
    error_message = "Bucket should have ManagedBy default tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Module"] == "storage/s3"
    error_message = "Bucket should have Module default tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "test-bucket"
    error_message = "Bucket should have Name tag matching bucket name."
  }
}

# Test: bucket has custom tags merged with defaults
run "test_bucket_custom_tags_merged" {
  command = plan

  variables {
    name = "test-bucket"
    tags = {
      Environment = "production"
      Team        = "platform"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["ManagedBy"] == "terraform"
    error_message = "Bucket should retain ManagedBy default tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Environment"] == "production"
    error_message = "Bucket should have custom Environment tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Team"] == "platform"
    error_message = "Bucket should have custom Team tag."
  }
}

#-------------------------------------------------------------------------------
# Public Access Block Tests
#-------------------------------------------------------------------------------

# Test: public access block defaults - all settings enabled
run "test_public_access_block_defaults" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "block_public_acls should default to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "block_public_policy should default to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == true
    error_message = "ignore_public_acls should default to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    error_message = "restrict_public_buckets should default to true."
  }
}

# Test: public access block can disable block_public_acls
run "test_public_access_block_disable_block_public_acls" {
  command = plan

  variables {
    name              = "test-bucket"
    block_public_acls = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == false
    error_message = "block_public_acls should be false when set."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "block_public_policy should remain true."
  }
}

# Test: public access block can disable block_public_policy
run "test_public_access_block_disable_block_public_policy" {
  command = plan

  variables {
    name                = "test-bucket"
    block_public_policy = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == false
    error_message = "block_public_policy should be false when set."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "block_public_acls should remain true."
  }
}

# Test: public access block can disable ignore_public_acls
run "test_public_access_block_disable_ignore_public_acls" {
  command = plan

  variables {
    name               = "test-bucket"
    ignore_public_acls = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == false
    error_message = "ignore_public_acls should be false when set."
  }
}

# Test: public access block can disable restrict_public_buckets
run "test_public_access_block_disable_restrict_public_buckets" {
  command = plan

  variables {
    name                    = "test-bucket"
    restrict_public_buckets = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == false
    error_message = "restrict_public_buckets should be false when set."
  }
}

# Test: public access block can disable all settings
run "test_public_access_block_all_disabled" {
  command = plan

  variables {
    name                    = "test-bucket"
    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == false
    error_message = "block_public_acls should be false."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == false
    error_message = "block_public_policy should be false."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == false
    error_message = "ignore_public_acls should be false."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == false
    error_message = "restrict_public_buckets should be false."
  }
}

# Test: public access block references correct bucket
run "test_public_access_block_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.bucket == aws_s3_bucket.this.id
    error_message = "Public access block should reference the correct bucket."
  }
}

#-------------------------------------------------------------------------------
# Server-Side Encryption Tests
#-------------------------------------------------------------------------------

# Test: encryption uses SSE-S3 (AES256) by default
run "test_encryption_sse_s3_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].sse_algorithm) == "AES256"
    error_message = "Encryption should use SSE-S3 (AES256) by default."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].kms_master_key_id) == null
    error_message = "KMS key should be null when using SSE-S3."
  }
}

# Test: encryption uses SSE-KMS when KMS key is provided
run "test_encryption_sse_kms_with_key" {
  command = plan

  variables {
    name       = "test-bucket"
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].sse_algorithm) == "aws:kms"
    error_message = "Encryption should use SSE-KMS when KMS key is provided."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].kms_master_key_id) == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "KMS key should be set when provided."
  }
}

# Test: bucket key is enabled by default for SSE-KMS
run "test_encryption_bucket_key_enabled_default" {
  command = plan

  variables {
    name       = "test-bucket"
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].bucket_key_enabled) == true
    error_message = "Bucket key should be enabled by default for SSE-KMS."
  }
}

# Test: bucket key can be disabled for SSE-KMS
run "test_encryption_bucket_key_disabled" {
  command = plan

  variables {
    name               = "test-bucket"
    kms_key_id         = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    bucket_key_enabled = false
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].bucket_key_enabled) == false
    error_message = "Bucket key should be disabled when set to false."
  }
}

# Test: encryption references correct bucket
run "test_encryption_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.bucket == aws_s3_bucket.this.id
    error_message = "Encryption configuration should reference the correct bucket."
  }
}

#-------------------------------------------------------------------------------
# Versioning Tests
#-------------------------------------------------------------------------------

# Test: versioning is disabled by default
run "test_versioning_disabled_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Disabled"
    error_message = "Versioning should be disabled by default."
  }
}

# Test: versioning can be enabled
run "test_versioning_enabled" {
  command = plan

  variables {
    name               = "test-bucket"
    versioning_enabled = true
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled when versioning_enabled is true."
  }
}

# Test: versioning references correct bucket
run "test_versioning_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.bucket == aws_s3_bucket.this.id
    error_message = "Versioning configuration should reference the correct bucket."
  }
}

# Test: versioning_enabled variable defaults to false
run "test_versioning_enabled_variable_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = var.versioning_enabled == false
    error_message = "versioning_enabled variable should default to false."
  }
}
