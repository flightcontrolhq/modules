################################################################################
# WAF Association
################################################################################

resource "aws_wafv2_web_acl_association" "this" {
  count = var.enable_waf_association ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl_arn

  lifecycle {
    precondition {
      condition     = var.web_acl_arn != null
      error_message = "When enable_waf_association is true, web_acl_arn must be provided."
    }
  }
}



