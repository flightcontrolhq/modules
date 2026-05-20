################################################################################
# hosting/static_site - Variable validation and Cache-Control wiring tests
#
# Variable validation rules cover input shape; the Cache-Control section
# verifies that the viewer-response CloudFront Function (added in ENG-4785) is
# wired up correctly and that its template substitutions reach the function
# body. Child-module behavior (storage/s3, cdn/cloudfront) is exercised by the
# per-module tests under their own `tests/` directories.
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
}

# CloudFront distribution, KVS, CloudFront Functions, and the optional
# response-headers policy all run through the us_east_1 alias. Their resource
# overrides live here so apply-mode tests don't hit the real CloudFront API
# and so resource arns are deterministic.
mock_provider "aws" {
  alias = "us_east_1"

  override_resource {
    target = aws_cloudfront_function.rewrite
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-rewrite"
    }
  }

  override_resource {
    target = aws_cloudfront_function.cache_control
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-cache-control"
    }
  }

  override_resource {
    target = aws_cloudfront_key_value_store.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:key-value-store/12345678-1234-1234-1234-123456789012"
      id  = "12345678-1234-1234-1234-123456789012"
    }
  }

  override_resource {
    target = aws_cloudfront_response_headers_policy.this
    values = {
      id = "module-rh-policy-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
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
# Cache-Control wiring (ENG-4785)
#
# A viewer-response CloudFront Function classifies every response by the
# rewritten URI shape and writes Cache-Control accordingly. The previous
# response-headers-policy approach could not see the rewritten URI, which is
# why SPA routes like `/dashboard` ended up with the immutable-assets header.
# These tests pin down: defaults, opt-out toggle, header values reaching the
# function body, override list reaching the function body, and the function
# being attached to every cache behavior.
#-------------------------------------------------------------------------------

run "cache_control_defaults" {
  command = plan

  assert {
    condition     = var.manage_cache_control == true
    error_message = "manage_cache_control should default to true."
  }

  assert {
    condition     = var.html_cache_control == "s-maxage=5, stale-while-revalidate=31536000"
    error_message = "html_cache_control should default to short s-maxage + long stale-while-revalidate."
  }

  assert {
    condition     = var.assets_cache_control == "public, max-age=31536000, immutable"
    error_message = "assets_cache_control should default to a 1-year immutable browser cache."
  }

  assert {
    condition     = contains(var.html_path_overrides, "/service-worker.js") && contains(var.html_path_overrides, "/favicon.ico") && contains(var.html_path_overrides, "/robots.txt")
    error_message = "html_path_overrides defaults must include service-worker, favicon, and robots.txt to keep stable root files off the immutable cache."
  }
}

run "cache_control_function_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_function.cache_control) == 1
    error_message = "viewer-response cache-control function must be created when manage_cache_control = true."
  }

  assert {
    condition     = length(local.cff_associations) == 2
    error_message = "Both the viewer-request rewriter and the viewer-response cache-control function must be associated with cache behaviors."
  }

  assert {
    condition     = local.cff_associations[0].event_type == "viewer-request" && local.cff_associations[1].event_type == "viewer-response"
    error_message = "viewer-request must run before viewer-response so cache-control sees the rewritten URI shape."
  }
}

run "cache_control_function_body_carries_template_values" {
  command = plan

  assert {
    condition     = strcontains(local.cff_cache_control_code, "s-maxage=5, stale-while-revalidate=31536000")
    error_message = "html_cache_control value must be substituted into the viewer-response function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "public, max-age=31536000, immutable")
    error_message = "assets_cache_control value must be substituted into the viewer-response function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "/service-worker.js") && strcontains(local.cff_cache_control_code, "/favicon.ico")
    error_message = "html_path_overrides entries must be substituted into the viewer-response function body so non-hashed root files don't get cached as immutable."
  }
}

run "cache_control_custom_overrides_flow_into_function" {
  command = plan

  variables {
    html_cache_control   = "no-store"
    assets_cache_control = "public, max-age=600"
    html_path_overrides  = ["/custom.txt", "/another.bin"]
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "no-store")
    error_message = "Caller override of html_cache_control must reach the function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "public, max-age=600")
    error_message = "Caller override of assets_cache_control must reach the function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "/custom.txt") && strcontains(local.cff_cache_control_code, "/another.bin")
    error_message = "Caller override of html_path_overrides must reach the function body."
  }
}

run "manage_cache_control_false_skips_function" {
  command = plan

  variables {
    manage_cache_control = false
  }

  assert {
    condition     = length(aws_cloudfront_function.cache_control) == 0
    error_message = "viewer-response cache-control function must NOT be created when manage_cache_control = false."
  }

  assert {
    condition     = length(local.cff_associations) == 1
    error_message = "Only the viewer-request rewriter must be associated when manage_cache_control = false."
  }

  assert {
    condition     = local.cff_associations[0].event_type == "viewer-request"
    error_message = "The remaining association must be the viewer-request rewriter."
  }
}

#-------------------------------------------------------------------------------
# Response-headers policy (security headers, CORS, custom headers)
#
# The module-managed policy is created on demand from var.response_headers_policy
# and carries security headers / CORS / arbitrary custom headers — Cache-Control
# stays the cache-control function's job. var.response_headers_policy_id remains
# as the override for callers with a centrally-managed policy.
#-------------------------------------------------------------------------------

run "response_headers_policy_defaults_to_no_resource" {
  command = plan

  assert {
    condition     = var.response_headers_policy == null
    error_message = "response_headers_policy must default to null so basic deployments don't allocate an unused policy resource."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "No module-managed response-headers policy should be created when response_headers_policy is null."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == null
    error_message = "Default behavior should attach no response-headers policy when neither response_headers_policy nor response_headers_policy_id is set."
  }
}

run "response_headers_policy_creates_resource_when_set" {
  command = apply

  variables {
    response_headers_policy = {
      security_headers_config = {
        strict_transport_security = {
          access_control_max_age_sec = 63072000
          include_subdomains         = true
          preload                    = true
        }
        content_security_policy = {
          content_security_policy = "default-src 'self'"
        }
        content_type_options = {}
        frame_options = {
          frame_option = "DENY"
        }
        referrer_policy = {
          referrer_policy = "strict-origin-when-cross-origin"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "Setting response_headers_policy.security_headers_config must create the module-managed policy."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "module-rh-policy-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "The default behavior must attach the module-managed policy id when response_headers_policy is set and response_headers_policy_id is not."
  }
}

run "response_headers_policy_supports_cors_custom_and_remove_headers" {
  command = apply

  variables {
    response_headers_policy = {
      cors_config = {
        access_control_allow_credentials = false
        access_control_allow_headers     = ["Content-Type", "Authorization"]
        access_control_allow_methods     = ["GET", "HEAD", "OPTIONS"]
        access_control_allow_origins     = ["https://app.example.com"]
        access_control_expose_headers    = ["X-Request-Id"]
        access_control_max_age_sec       = 600
      }
      custom_headers = [
        {
          header = "Permissions-Policy"
          value  = "camera=(), microphone=()"
        },
        {
          header = "Cross-Origin-Opener-Policy"
          value  = "same-origin"
        },
      ]
      remove_headers = ["Server", "X-Powered-By"]
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "Setting response_headers_policy with cors / custom_headers / remove_headers must create the policy."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].cors_config) == 1
    error_message = "cors_config block must be present on the policy when var.response_headers_policy.cors_config is set."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].custom_headers_config) == 1
    error_message = "custom_headers_config block must be present when var.response_headers_policy.custom_headers is non-empty."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].remove_headers_config) == 1
    error_message = "remove_headers_config block must be present when var.response_headers_policy.remove_headers is non-empty."
  }
}

run "response_headers_policy_skips_unset_blocks" {
  command = apply

  variables {
    response_headers_policy = {
      security_headers_config = {
        content_type_options = {}
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config) == 1
    error_message = "security_headers_config block must be present when set on the variable."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].cors_config) == 0
    error_message = "cors_config block must NOT be created when the variable's cors_config field is null."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].custom_headers_config) == 0
    error_message = "custom_headers_config block must NOT be created when custom_headers is empty."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].remove_headers_config) == 0
    error_message = "remove_headers_config block must NOT be created when remove_headers is empty."
  }
}

run "response_headers_policy_id_overrides_module_managed" {
  command = apply

  variables {
    response_headers_policy_id = "11111111-2222-3333-4444-555555555555"
    response_headers_policy = {
      security_headers_config = {
        content_type_options = {}
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "The module-managed policy is still created — the output remains available for use elsewhere."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "11111111-2222-3333-4444-555555555555"
    error_message = "When both response_headers_policy_id and response_headers_policy are set, the caller-supplied id wins on the default behavior."
  }
}

run "response_headers_policy_validates_frame_option" {
  command = plan

  variables {
    response_headers_policy = {
      security_headers_config = {
        frame_options = {
          frame_option = "ALLOW"
        }
      }
    }
  }

  expect_failures = [var.response_headers_policy]
}

run "response_headers_policy_id_alone_works_without_module_policy" {
  command = apply

  variables {
    response_headers_policy_id = "22222222-3333-4444-5555-666666666666"
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "When only response_headers_policy_id is set, no module-managed policy resource should be created."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "22222222-3333-4444-5555-666666666666"
    error_message = "The caller-supplied id must be attached to the default behavior."
  }

  assert {
    condition     = length(aws_cloudfront_function.cache_control) == 1
    error_message = "The cache-control function must coexist with a caller-supplied response-headers policy — they handle orthogonal concerns."
  }
}
