################################################################################
# CloudFront Cache Policy (module-managed)
#
# Created when var.cache_policy_id is null (the default). Mirrors the
# AWS-managed CachingOptimized policy — no cookies, headers, or query strings
# in the cache key, gzip + brotli compression support — but raises the default
# TTL from 24 hours to 1 year. S3 sends no Cache-Control headers, so the
# policy's default TTL is what governs edge cache lifetime, and the versioned
# cache key makes long edge caching safe: every promotion changes the key, so
# stale entries are never served after a deploy.
################################################################################

resource "aws_cloudfront_cache_policy" "this" {
  count = var.cache_policy_id == null ? 1 : 0

  provider = aws.us_east_1

  name    = local.cache_policy_name
  comment = "Long edge cache for ${var.name} - versioned cache keys make 1-year TTLs safe"

  min_ttl     = 1
  default_ttl = 31536000
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}
