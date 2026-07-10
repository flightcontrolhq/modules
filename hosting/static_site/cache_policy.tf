resource "aws_cloudfront_cache_policy" "swr" {
  count = local.swr_enabled ? 1 : 0

  provider = aws.us_east_1

  name        = local.swr_cache_policy_name
  comment     = "Stable Host-partitioned cache keys for ${var.name}"
  default_ttl = 5
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Host"]
      }
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

resource "aws_cloudfront_origin_request_policy" "swr" {
  count = local.swr_enabled ? 1 : 0

  provider = aws.us_east_1

  name    = local.swr_origin_policy_name
  comment = "Forward the active Ravion version without forwarding Host to S3"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["X-Ravion-Version"]
    }
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}
