################################################################################
# CloudFront Response Headers Policy (module-managed)
#
# Created when var.response_headers_policy is non-null. Carries security
# headers (HSTS, CSP, X-Frame-Options, Referrer-Policy, X-Content-Type-Options
# nosniff, optional XSS protection), CORS configuration, arbitrary custom
# response headers, and stripped headers — anything the AWS resource supports
# *except* Cache-Control, which is written by the viewer-response cache-control
# function (see functions/cache_control.js).
#
# Attaches to the default cache behavior unless the caller supplies their own
# `var.response_headers_policy_id`, which always wins. Callers who manage
# their policy externally (org-wide CSP, centralised security baseline) can
# keep using `response_headers_policy_id`; callers who want a per-site policy
# configured declaratively use `response_headers_policy`.
################################################################################

resource "aws_cloudfront_response_headers_policy" "this" {
  count = var.response_headers_policy != null ? 1 : 0

  provider = aws.us_east_1

  name    = local.response_headers_policy_name
  comment = "Module-managed response headers (security/CORS/custom) for ${var.name}"

  dynamic "security_headers_config" {
    for_each = var.response_headers_policy.security_headers_config != null ? [var.response_headers_policy.security_headers_config] : []

    content {
      dynamic "strict_transport_security" {
        for_each = security_headers_config.value.strict_transport_security != null ? [security_headers_config.value.strict_transport_security] : []
        content {
          access_control_max_age_sec = strict_transport_security.value.access_control_max_age_sec
          include_subdomains         = strict_transport_security.value.include_subdomains
          preload                    = strict_transport_security.value.preload
          override                   = strict_transport_security.value.override
        }
      }

      dynamic "content_security_policy" {
        for_each = security_headers_config.value.content_security_policy != null ? [security_headers_config.value.content_security_policy] : []
        content {
          content_security_policy = content_security_policy.value.content_security_policy
          override                = content_security_policy.value.override
        }
      }

      dynamic "content_type_options" {
        for_each = security_headers_config.value.content_type_options != null ? [security_headers_config.value.content_type_options] : []
        content {
          override = content_type_options.value.override
        }
      }

      dynamic "frame_options" {
        for_each = security_headers_config.value.frame_options != null ? [security_headers_config.value.frame_options] : []
        content {
          frame_option = frame_options.value.frame_option
          override     = frame_options.value.override
        }
      }

      dynamic "referrer_policy" {
        for_each = security_headers_config.value.referrer_policy != null ? [security_headers_config.value.referrer_policy] : []
        content {
          referrer_policy = referrer_policy.value.referrer_policy
          override        = referrer_policy.value.override
        }
      }

      dynamic "xss_protection" {
        for_each = security_headers_config.value.xss_protection != null ? [security_headers_config.value.xss_protection] : []
        content {
          protection = xss_protection.value.protection
          mode_block = xss_protection.value.mode_block
          report_uri = xss_protection.value.report_uri
          override   = xss_protection.value.override
        }
      }
    }
  }

  dynamic "cors_config" {
    for_each = var.response_headers_policy.cors_config != null ? [var.response_headers_policy.cors_config] : []

    content {
      access_control_allow_credentials = cors_config.value.access_control_allow_credentials
      access_control_max_age_sec       = cors_config.value.access_control_max_age_sec
      origin_override                  = cors_config.value.origin_override

      access_control_allow_headers {
        items = cors_config.value.access_control_allow_headers
      }

      access_control_allow_methods {
        items = cors_config.value.access_control_allow_methods
      }

      access_control_allow_origins {
        items = cors_config.value.access_control_allow_origins
      }

      access_control_expose_headers {
        items = cors_config.value.access_control_expose_headers
      }
    }
  }

  dynamic "custom_headers_config" {
    for_each = length(var.response_headers_policy.custom_headers) > 0 ? [var.response_headers_policy.custom_headers] : []

    content {
      dynamic "items" {
        for_each = custom_headers_config.value
        content {
          header   = items.value.header
          value    = items.value.value
          override = items.value.override
        }
      }
    }
  }

  dynamic "remove_headers_config" {
    for_each = length(var.response_headers_policy.remove_headers) > 0 ? [var.response_headers_policy.remove_headers] : []

    content {
      dynamic "items" {
        for_each = remove_headers_config.value
        content {
          header = items.value
        }
      }
    }
  }
}
