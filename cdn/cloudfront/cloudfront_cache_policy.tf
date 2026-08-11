resource "aws_cloudfront_cache_policy" "accept_header" {
  count = var.accept_header_cache_key_creation_enabled ? 1 : 0

  name    = "${var.name}-accept-header"
  comment = "Use origin cache control headers and include normalized Markdown negotiation in the cache key"

  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["x-md"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }

  # Order distribution detachment before deleting the policy.
  lifecycle {
    create_before_destroy = true
  }
}
