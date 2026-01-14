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
