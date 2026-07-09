resource "aws_cloudfront_function" "redirect" {
  count = local.redirects_enabled ? 1 : 0

  name    = local.redirect_function_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} viewer-request redirects"
  publish = true
  code    = local.redirect_function_code

  lifecycle {
    precondition {
      condition     = length(local.redirect_function_code) <= 10240
      error_message = "The generated redirect function exceeds CloudFront Functions' 10 KB code limit. Reduce the number or length of redirect rules."
    }
  }
}
