################################################################################
# hosting/static_site - Variable validation tests
#
# These tests focus on input variable validation rules. Child-module behavior
# (storage/s3, cdn/cloudfront, compute/lambda) is exercised by the per-module
# tests under their own `tests/` directories; here we only verify that this
# composite accepts/rejects the right inputs.
################################################################################

mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.hosting_bucket_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.lambda_edge_s3_read
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.deploy_role_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_cloudfront_function.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-fn"
    }
  }

  override_resource {
    target = aws_cloudfront_key_value_store.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:key-value-store/12345678-1234-1234-1234-123456789012"
      id  = "12345678-1234-1234-1234-123456789012"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  name = "ravion-test-site"
}

#-------------------------------------------------------------------------------
# Mode validation
#-------------------------------------------------------------------------------

run "mode_default_is_spa" {
  command = plan

  assert {
    condition     = var.mode == "spa"
    error_message = "mode should default to 'spa'."
  }
}

run "mode_accepts_filesystem" {
  command = plan

  variables {
    mode = "filesystem"
  }

  assert {
    condition     = var.mode == "filesystem"
    error_message = "mode should accept 'filesystem'."
  }
}

run "mode_rejects_unknown" {
  command = plan

  variables {
    mode = "ssr"
  }

  expect_failures = [var.mode]
}

#-------------------------------------------------------------------------------
# Name validation (S3 bucket name rules)
#-------------------------------------------------------------------------------

run "name_rejects_uppercase" {
  command = plan

  variables {
    name = "Ravion-Test-Site"
  }

  expect_failures = [var.name]
}

run "name_rejects_underscores" {
  command = plan

  variables {
    name = "ravion_test_site"
  }

  expect_failures = [var.name]
}

run "name_rejects_too_short" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "name_rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-ravion"
  }

  expect_failures = [var.name]
}

#-------------------------------------------------------------------------------
# Distributions
#-------------------------------------------------------------------------------

run "distributions_default_to_main" {
  command = plan

  assert {
    condition     = contains(keys(var.distributions), "main")
    error_message = "distributions should default to a 'main' entry."
  }
}

run "distributions_rejects_empty" {
  command = plan

  variables {
    distributions = {}
  }

  expect_failures = [var.distributions]
}

#-------------------------------------------------------------------------------
# Lambda@Edge constraints
#-------------------------------------------------------------------------------

run "lambda_timeout_rejects_above_30" {
  command = plan

  variables {
    lambda_timeout = 60
  }

  expect_failures = [var.lambda_timeout]
}

run "lambda_memory_rejects_above_3008" {
  command = plan

  variables {
    lambda_memory_size = 4096
  }

  expect_failures = [var.lambda_memory_size]
}

run "lambda_runtime_rejects_python" {
  command = plan

  variables {
    lambda_runtime = "python3.12"
  }

  expect_failures = [var.lambda_runtime]
}

#-------------------------------------------------------------------------------
# Static mode header
#-------------------------------------------------------------------------------

run "static_mode_rejects_invalid" {
  command = plan

  variables {
    static_mode_header_value = "ssr"
  }

  expect_failures = [var.static_mode_header_value]
}

#-------------------------------------------------------------------------------
# Geo restrictions
#-------------------------------------------------------------------------------

run "geo_restriction_type_rejects_invalid" {
  command = plan

  variables {
    geo_restriction_type = "deny"
  }

  expect_failures = [var.geo_restriction_type]
}

#-------------------------------------------------------------------------------
# WAF
#-------------------------------------------------------------------------------

run "web_acl_id_rejects_non_wafv2" {
  command = plan

  variables {
    web_acl_id = "arn:aws:waf::123456789012:webacl/my-acl"
  }

  expect_failures = [var.web_acl_id]
}

run "web_acl_id_accepts_valid_arn" {
  command = plan

  variables {
    web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc-123"
  }

  assert {
    condition     = var.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc-123"
    error_message = "Valid WAFv2 ARN should be accepted."
  }
}

#-------------------------------------------------------------------------------
# KMS
#-------------------------------------------------------------------------------

run "kms_key_arn_rejects_invalid" {
  command = plan

  variables {
    kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}

#-------------------------------------------------------------------------------
# Deploy role
#-------------------------------------------------------------------------------

run "deploy_role_trust_policy_rejects_invalid_json" {
  command = plan

  variables {
    deploy_role_trust_policy = "not json {{"
  }

  expect_failures = [var.deploy_role_trust_policy]
}
