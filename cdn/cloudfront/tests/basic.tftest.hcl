################################################################################
# CloudFront Module Unit Tests
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

  override_resource {
    target = aws_cloudfront_distribution.this
    values = {
      arn                            = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
      domain_name                    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id                 = "Z2FDTNDATAQYW2"
      status                         = "Deployed"
      etag                           = "E2QWRUHEXAMPLE"
      id                             = "EDFDVBD6EXAMPLE"
      caller_reference               = "test-ref-001"
      in_progress_validation_batches = 0
    }
  }

  override_resource {
    target = aws_s3_bucket.logging
    values = {
      arn         = "arn:aws:s3:::test-cf-logs-123456789012-us-east-1"
      id          = "test-cf-logs-123456789012-us-east-1"
      bucket      = "test-cf-logs-123456789012-us-east-1"
      domain_name = "test-cf-logs-123456789012-us-east-1.s3.amazonaws.com"
    }
  }
}

# Default variables for all tests
variables {
  name = "test-cf"
  distributions = {
    primary = {}
  }
  origins = [
    {
      origin_id   = "s3-origin"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin   = true
    }
  ]
  default_cache_behavior = {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
  }
}

#-------------------------------------------------------------------------------
# Name Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid name - basic
run "test_name_validation_valid_basic" {
  command = plan

  assert {
    condition     = var.name == "test-cf"
    error_message = "Valid name should be accepted."
  }
}

# Test: Valid name - with numbers
run "test_name_validation_valid_with_numbers" {
  command = plan

  variables {
    name = "cf123test"
  }

  assert {
    condition     = var.name == "cf123test"
    error_message = "Valid name with numbers should be accepted."
  }
}

# Test: Invalid name - empty
run "test_name_validation_empty" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - too long (more than 63 characters)
run "test_name_validation_max_length" {
  command = plan

  variables {
    name = "this-cloudfront-name-is-way-too-long-and-exceeds-the-sixty-three-character-limit"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - starts with number
run "test_name_validation_starts_with_number" {
  command = plan

  variables {
    name = "123-invalid"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - contains underscores
run "test_name_validation_invalid_underscore" {
  command = plan

  variables {
    name = "my_test_cf"
  }

  expect_failures = [
    var.name,
  ]
}

#-------------------------------------------------------------------------------
# Distributions Validation Tests
#-------------------------------------------------------------------------------

# Test: Invalid distributions - empty map
run "test_distributions_empty" {
  command = plan

  variables {
    distributions = {}
  }

  expect_failures = [
    var.distributions,
  ]
}

# Test: Valid distributions - single with defaults
run "test_distributions_single_defaults" {
  command = plan

  variables {
    distributions = {
      primary = {}
    }
  }

  assert {
    condition     = var.distributions["primary"].enabled == true
    error_message = "Distribution enabled should default to true."
  }

  assert {
    condition     = length(var.distributions["primary"].aliases) == 0
    error_message = "Distribution aliases should default to empty list."
  }
}

# Test: Valid distributions - multiple distributions
run "test_distributions_multiple" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["example.com", "www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
      staging = {
        aliases             = ["staging.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/87654321-4321-4321-4321-210987654321"
        comment             = "Staging distribution"
      }
    }
  }

  assert {
    condition     = length(var.distributions) == 2
    error_message = "Two distributions should be accepted."
  }
}

# Test: Invalid distributions - aliases without cert
run "test_distributions_aliases_without_cert" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases = ["example.com"]
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

# Test: Invalid distributions - invalid ACM ARN
run "test_distributions_invalid_acm_arn" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["example.com"]
        acm_certificate_arn = "arn:aws:iam::123456789012:role/my-role"
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

# Test: Invalid distributions - duplicate aliases across distributions
run "test_distributions_duplicate_aliases" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["example.com", "www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
      secondary = {
        aliases             = ["example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/87654321-4321-4321-4321-210987654321"
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

#-------------------------------------------------------------------------------
# Price Class Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid price_class - PriceClass_100
run "test_price_class_valid_100" {
  command = plan

  variables {
    price_class = "PriceClass_100"
  }

  assert {
    condition     = var.price_class == "PriceClass_100"
    error_message = "PriceClass_100 should be accepted."
  }
}

# Test: Valid price_class - PriceClass_200
run "test_price_class_valid_200" {
  command = plan

  variables {
    price_class = "PriceClass_200"
  }

  assert {
    condition     = var.price_class == "PriceClass_200"
    error_message = "PriceClass_200 should be accepted."
  }
}

# Test: Valid price_class - PriceClass_All
run "test_price_class_valid_all" {
  command = plan

  variables {
    price_class = "PriceClass_All"
  }

  assert {
    condition     = var.price_class == "PriceClass_All"
    error_message = "PriceClass_All should be accepted."
  }
}

# Test: Invalid price_class
run "test_price_class_invalid" {
  command = plan

  variables {
    price_class = "PriceClass_Invalid"
  }

  expect_failures = [
    var.price_class,
  ]
}

#-------------------------------------------------------------------------------
# HTTP Version Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid http_version - http2and3
run "test_http_version_valid_http2and3" {
  command = plan

  assert {
    condition     = var.http_version == "http2and3"
    error_message = "http2and3 should be the default."
  }
}

# Test: Valid http_version - http2
run "test_http_version_valid_http2" {
  command = plan

  variables {
    http_version = "http2"
  }

  assert {
    condition     = var.http_version == "http2"
    error_message = "http2 should be accepted."
  }
}

# Test: Invalid http_version
run "test_http_version_invalid" {
  command = plan

  variables {
    http_version = "http3"
  }

  expect_failures = [
    var.http_version,
  ]
}

#-------------------------------------------------------------------------------
# Geo Restriction Type Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid geo_restriction_type - none (default)
run "test_geo_restriction_type_valid_none" {
  command = plan

  assert {
    condition     = var.geo_restriction_type == "none"
    error_message = "none should be the default geo_restriction_type."
  }
}

# Test: Valid geo_restriction_type - whitelist
run "test_geo_restriction_type_valid_whitelist" {
  command = plan

  variables {
    geo_restriction_type      = "whitelist"
    geo_restriction_locations = ["US", "CA"]
  }

  assert {
    condition     = var.geo_restriction_type == "whitelist"
    error_message = "whitelist should be accepted."
  }
}

# Test: Valid geo_restriction_type - blacklist
run "test_geo_restriction_type_valid_blacklist" {
  command = plan

  variables {
    geo_restriction_type      = "blacklist"
    geo_restriction_locations = ["CN", "RU"]
  }

  assert {
    condition     = var.geo_restriction_type == "blacklist"
    error_message = "blacklist should be accepted."
  }
}

# Test: Invalid geo_restriction_type
run "test_geo_restriction_type_invalid" {
  command = plan

  variables {
    geo_restriction_type = "allow"
  }

  expect_failures = [
    var.geo_restriction_type,
  ]
}

#-------------------------------------------------------------------------------
# Viewer Protocol Policy Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid viewer_protocol_policy - redirect-to-https
run "test_viewer_protocol_policy_valid_redirect" {
  command = plan

  assert {
    condition     = var.default_cache_behavior.viewer_protocol_policy == "redirect-to-https"
    error_message = "redirect-to-https should be accepted."
  }
}

# Test: Valid viewer_protocol_policy - https-only
run "test_viewer_protocol_policy_valid_https_only" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "https-only"
    }
  }

  assert {
    condition     = var.default_cache_behavior.viewer_protocol_policy == "https-only"
    error_message = "https-only should be accepted."
  }
}

# Test: Valid viewer_protocol_policy - allow-all
run "test_viewer_protocol_policy_valid_allow_all" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "allow-all"
    }
  }

  assert {
    condition     = var.default_cache_behavior.viewer_protocol_policy == "allow-all"
    error_message = "allow-all should be accepted."
  }
}

# Test: Invalid viewer_protocol_policy
run "test_viewer_protocol_policy_invalid" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "http-only"
    }
  }

  expect_failures = [
    var.default_cache_behavior,
  ]
}

#-------------------------------------------------------------------------------
# SSL Support Method Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid ssl_support_method - sni-only (default)
run "test_ssl_support_method_valid_sni_only" {
  command = plan

  assert {
    condition     = var.ssl_support_method == "sni-only"
    error_message = "sni-only should be the default."
  }
}

# Test: Valid ssl_support_method - vip
run "test_ssl_support_method_valid_vip" {
  command = plan

  variables {
    ssl_support_method = "vip"
  }

  assert {
    condition     = var.ssl_support_method == "vip"
    error_message = "vip should be accepted."
  }
}

# Test: Invalid ssl_support_method
run "test_ssl_support_method_invalid" {
  command = plan

  variables {
    ssl_support_method = "dedicated-ip"
  }

  expect_failures = [
    var.ssl_support_method,
  ]
}

#-------------------------------------------------------------------------------
# WAF Web ACL ARN Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid web_acl_id - null (default)
run "test_web_acl_id_valid_null" {
  command = plan

  assert {
    condition     = var.web_acl_id == null
    error_message = "web_acl_id should default to null."
  }
}

# Test: Valid web_acl_id - valid ARN
run "test_web_acl_id_valid_arn" {
  command = plan

  variables {
    web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = var.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/12345678-1234-1234-1234-123456789012"
    error_message = "Valid WAFv2 ARN should be accepted."
  }
}

# Test: Invalid web_acl_id - not a WAFv2 ARN
run "test_web_acl_id_invalid" {
  command = plan

  variables {
    web_acl_id = "arn:aws:waf::123456789012:webacl/my-acl"
  }

  expect_failures = [
    var.web_acl_id,
  ]
}

#-------------------------------------------------------------------------------
# Minimum Protocol Version Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid minimum_protocol_version - default
run "test_minimum_protocol_version_valid_default" {
  command = plan

  assert {
    condition     = var.minimum_protocol_version == "TLSv1.2_2021"
    error_message = "TLSv1.2_2021 should be the default."
  }
}

# Test: Valid minimum_protocol_version - TLSv1.2_2019
run "test_minimum_protocol_version_valid_2019" {
  command = plan

  variables {
    minimum_protocol_version = "TLSv1.2_2019"
  }

  assert {
    condition     = var.minimum_protocol_version == "TLSv1.2_2019"
    error_message = "TLSv1.2_2019 should be accepted."
  }
}

# Test: Invalid minimum_protocol_version
run "test_minimum_protocol_version_invalid" {
  command = plan

  variables {
    minimum_protocol_version = "TLSv1.3"
  }

  expect_failures = [
    var.minimum_protocol_version,
  ]
}

#-------------------------------------------------------------------------------
# Origin Validation Tests
#-------------------------------------------------------------------------------

# Test: Invalid origins - empty list
run "test_origins_validation_empty" {
  command = plan

  variables {
    origins = []
  }

  expect_failures = [
    var.origins,
  ]
}

# Test: Invalid origins - duplicate origin_id
run "test_origins_validation_duplicate_id" {
  command = plan

  variables {
    origins = [
      {
        origin_id   = "same-id"
        domain_name = "bucket1.s3.amazonaws.com"
        s3_origin   = true
      },
      {
        origin_id   = "same-id"
        domain_name = "bucket2.s3.amazonaws.com"
        s3_origin   = true
      }
    ]
  }

  expect_failures = [
    var.origins,
  ]
}

# Test: Valid origins - multiple origins
run "test_origins_validation_multiple" {
  command = plan

  variables {
    origins = [
      {
        origin_id   = "s3-origin"
        domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
        s3_origin   = true
      },
      {
        origin_id   = "alb-origin"
        domain_name = "my-alb-123.us-east-1.elb.amazonaws.com"
      }
    ]
  }

  assert {
    condition     = length(var.origins) == 2
    error_message = "Two origins should be accepted."
  }
}

#-------------------------------------------------------------------------------
# Logging Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid logging_bucket_retention_days
run "test_logging_retention_valid" {
  command = plan

  variables {
    logging_bucket_retention_days = 30
  }

  assert {
    condition     = var.logging_bucket_retention_days == 30
    error_message = "30 days retention should be accepted."
  }
}

# Test: Invalid logging_bucket_retention_days - zero
run "test_logging_retention_invalid_zero" {
  command = plan

  variables {
    logging_bucket_retention_days = 0
  }

  expect_failures = [
    var.logging_bucket_retention_days,
  ]
}

#-------------------------------------------------------------------------------
# Origin Access Control Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid origin_access_control_origin_type - s3 (default)
run "test_oac_origin_type_valid_s3" {
  command = plan

  assert {
    condition     = var.origin_access_control_origin_type == "s3"
    error_message = "s3 should be the default OAC origin type."
  }
}

# Test: Invalid origin_access_control_origin_type
run "test_oac_origin_type_invalid" {
  command = plan

  variables {
    origin_access_control_origin_type = "ec2"
  }

  expect_failures = [
    var.origin_access_control_origin_type,
  ]
}

# Test: Valid origin_access_control_signing_behavior - always (default)
run "test_oac_signing_behavior_valid_always" {
  command = plan

  assert {
    condition     = var.origin_access_control_signing_behavior == "always"
    error_message = "always should be the default signing behavior."
  }
}

# Test: Invalid origin_access_control_signing_behavior
run "test_oac_signing_behavior_invalid" {
  command = plan

  variables {
    origin_access_control_signing_behavior = "sometimes"
  }

  expect_failures = [
    var.origin_access_control_signing_behavior,
  ]
}

# Test: Invalid origin_access_control_signing_protocol
run "test_oac_signing_protocol_invalid" {
  command = plan

  variables {
    origin_access_control_signing_protocol = "sigv2"
  }

  expect_failures = [
    var.origin_access_control_signing_protocol,
  ]
}

#-------------------------------------------------------------------------------
# Custom Error Responses Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid custom_error_responses
run "test_custom_error_responses_valid" {
  command = plan

  variables {
    custom_error_responses = [
      {
        error_code         = 404
        response_code      = 200
        response_page_path = "/index.html"
      }
    ]
  }

  assert {
    condition     = length(var.custom_error_responses) == 1
    error_message = "Valid custom error response should be accepted."
  }
}

# Test: Invalid custom_error_responses - unsupported error code
run "test_custom_error_responses_invalid_code" {
  command = plan

  variables {
    custom_error_responses = [
      {
        error_code = 200
      }
    ]
  }

  expect_failures = [
    var.custom_error_responses,
  ]
}

#-------------------------------------------------------------------------------
# Default Value Tests
#-------------------------------------------------------------------------------

# Test: All defaults
run "test_defaults" {
  command = plan

  assert {
    condition     = var.price_class == "PriceClass_100"
    error_message = "price_class should default to PriceClass_100."
  }

  assert {
    condition     = var.http_version == "http2and3"
    error_message = "http_version should default to http2and3."
  }

  assert {
    condition     = var.is_ipv6_enabled == true
    error_message = "is_ipv6_enabled should default to true."
  }

  assert {
    condition     = var.default_root_object == null
    error_message = "default_root_object should default to null."
  }

  assert {
    condition     = var.retain_on_delete == false
    error_message = "retain_on_delete should default to false."
  }

  assert {
    condition     = var.wait_for_deployment == true
    error_message = "wait_for_deployment should default to true."
  }

  assert {
    condition     = var.minimum_protocol_version == "TLSv1.2_2021"
    error_message = "minimum_protocol_version should default to TLSv1.2_2021."
  }

  assert {
    condition     = var.ssl_support_method == "sni-only"
    error_message = "ssl_support_method should default to sni-only."
  }

  assert {
    condition     = var.geo_restriction_type == "none"
    error_message = "geo_restriction_type should default to none."
  }

  assert {
    condition     = length(var.geo_restriction_locations) == 0
    error_message = "geo_restriction_locations should default to empty list."
  }

  assert {
    condition     = var.web_acl_id == null
    error_message = "web_acl_id should default to null."
  }

  assert {
    condition     = var.enable_logging == false
    error_message = "enable_logging should default to false."
  }

  assert {
    condition     = var.create_logging_bucket == false
    error_message = "create_logging_bucket should default to false."
  }

  assert {
    condition     = var.logging_bucket_retention_days == 90
    error_message = "logging_bucket_retention_days should default to 90."
  }

  assert {
    condition     = var.logging_include_cookies == false
    error_message = "logging_include_cookies should default to false."
  }

  assert {
    condition     = var.create_origin_access_control == true
    error_message = "create_origin_access_control should default to true."
  }

  assert {
    condition     = length(var.ordered_cache_behaviors) == 0
    error_message = "ordered_cache_behaviors should default to empty list."
  }

  assert {
    condition     = length(var.custom_error_responses) == 0
    error_message = "custom_error_responses should default to empty list."
  }

  assert {
    condition     = var.default_cache_behavior.compress == true
    error_message = "compress should default to true in default_cache_behavior."
  }
}
