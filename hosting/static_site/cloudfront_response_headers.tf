################################################################################
# CloudFront Response Headers Policies
#
# Two module-managed policies drive the default Cache-Control behavior:
#
# - `html`   : short s-maxage + long stale-while-revalidate. Attached to the
#              `*.html` ordered behavior so the entry document propagates new
#              versions within seconds while never blocking on a cache miss.
# - `assets` : long-lived browser cache for everything else. Hashed/versioned
#              asset URLs make these effectively immutable.
#
# Both policies override the origin's Cache-Control by default so CloudFront
# is the single source of truth regardless of S3 object metadata. Callers can
# disable individual policies via *_override variables, swap header values via
# the *_cache_control variables, or opt out of the whole feature with
# `manage_response_headers_policies = false`.
################################################################################

resource "aws_cloudfront_response_headers_policy" "html" {
  count   = var.manage_response_headers_policies ? 1 : 0
  name    = substr(replace("${var.name}-html-rh", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  comment = "Short s-maxage + long SWR for HTML documents (${var.name})"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      value    = var.html_cache_control
      override = var.html_cache_control_override
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "assets" {
  count   = var.manage_response_headers_policies ? 1 : 0
  name    = substr(replace("${var.name}-assets-rh", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  comment = "Long-lived browser cache for hashed/versioned assets (${var.name})"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      value    = var.assets_cache_control
      override = var.assets_cache_control_override
    }
  }
}
