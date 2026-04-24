################################################################################
# hosting/static_site - Variable validation tests
#
# These tests focus on input variable validation rules. Child-module behavior
# (storage/s3, cdn/cloudfront) is exercised by the per-module tests under their
# own `tests/` directories; here we only verify that this composite accepts and
# rejects the right inputs.
################################################################################

mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.hosting_bucket_policy
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

variables {
  name = "ravion-test-site"
}

#-------------------------------------------------------------------------------
# Routing validation
#-------------------------------------------------------------------------------

run "routing_default_is_spa" {
  command = plan

  assert {
    condition     = var.routing == "spa"
    error_message = "routing should default to 'spa'."
  }
}

run "routing_accepts_filesystem" {
  command = plan

  variables {
    routing = "filesystem"
  }

  assert {
    condition     = var.routing == "filesystem"
    error_message = "routing should accept 'filesystem'."
  }
}

run "routing_rejects_unknown" {
  command = plan

  variables {
    routing = "ssr"
  }

  expect_failures = [var.routing]
}

#-------------------------------------------------------------------------------
# default_version validation
#-------------------------------------------------------------------------------

run "default_version_default_is_main" {
  command = plan

  assert {
    condition     = var.default_version == "main"
    error_message = "default_version should default to 'main'."
  }
}

run "default_version_accepts_versions_prefix" {
  command = plan

  variables {
    default_version = "versions/v1"
  }

  assert {
    condition     = var.default_version == "versions/v1"
    error_message = "default_version should accept 'versions/v1'."
  }
}

run "default_version_rejects_invalid_chars" {
  command = plan

  variables {
    default_version = "v 1!"
  }

  expect_failures = [var.default_version]
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

#-------------------------------------------------------------------------------
# Response headers policies (defaults)
#-------------------------------------------------------------------------------

run "manage_response_headers_policies_defaults_to_true" {
  command = plan

  assert {
    condition     = var.manage_response_headers_policies == true
    error_message = "manage_response_headers_policies should default to true."
  }
}

run "html_cache_control_default" {
  command = plan

  assert {
    condition     = var.html_cache_control == "s-maxage=5, stale-while-revalidate=31536000"
    error_message = "html_cache_control should default to short s-maxage + long stale-while-revalidate."
  }
}

run "html_cache_control_override_defaults_to_true" {
  command = plan

  assert {
    condition     = var.html_cache_control_override == true
    error_message = "html_cache_control_override should default to true so CloudFront wins over S3 metadata."
  }
}

run "assets_cache_control_default" {
  command = plan

  assert {
    condition     = var.assets_cache_control == "public, max-age=31536000, immutable"
    error_message = "assets_cache_control should default to a 1-year immutable browser cache."
  }
}

run "assets_cache_control_override_defaults_to_true" {
  command = plan

  assert {
    condition     = var.assets_cache_control_override == true
    error_message = "assets_cache_control_override should default to true so CloudFront wins over S3 metadata."
  }
}

run "html_path_pattern_default" {
  command = plan

  assert {
    condition     = var.html_path_pattern == "*.html"
    error_message = "html_path_pattern should default to '*.html'."
  }
}

run "default_creates_html_and_assets_policies" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.html) == 1
    error_message = "html response headers policy should be created by default."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.assets) == 1
    error_message = "assets response headers policy should be created by default."
  }

  assert {
    condition     = length(local.html_cache_behaviors) == 1
    error_message = "an ordered cache behavior for *.html should be present by default."
  }

  assert {
    condition     = local.html_cache_behaviors[0].path_pattern == "*.html"
    error_message = "the html ordered cache behavior should target the *.html path pattern."
  }
}

run "manage_response_headers_policies_false_skips_resources" {
  command = plan

  variables {
    manage_response_headers_policies = false
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.html) == 0
    error_message = "html response headers policy should not be created when manage_response_headers_policies = false."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.assets) == 0
    error_message = "assets response headers policy should not be created when manage_response_headers_policies = false."
  }

  assert {
    condition     = length(local.html_cache_behaviors) == 0
    error_message = "no html ordered cache behavior should be added when manage_response_headers_policies = false."
  }

  assert {
    condition     = local.effective_default_response_headers_policy_id == null
    error_message = "default behavior should attach no response headers policy when both manage flag and var.response_headers_policy_id are unset."
  }
}

run "caller_supplied_response_headers_policy_id_wins_on_default" {
  command = plan

  variables {
    response_headers_policy_id = "11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = local.effective_default_response_headers_policy_id == "11111111-2222-3333-4444-555555555555"
    error_message = "Caller-supplied response_headers_policy_id should take precedence on the default behavior."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.html) == 1
    error_message = "html response headers policy should still be created when the caller supplies their own default policy."
  }
}

run "html_path_pattern_override_flows_through" {
  command = plan

  variables {
    html_path_pattern = "*.htm"
  }

  assert {
    condition     = local.html_cache_behaviors[0].path_pattern == "*.htm"
    error_message = "html_path_pattern override should flow into the ordered cache behavior."
  }
}
