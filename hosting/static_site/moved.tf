################################################################################
# State moves
#
# Preserve the viewer-request function through both historical resource
# renames. The current hashed AWS name then produces a managed replacement:
# create the new function, update the distribution, and delete the old one.
#
# The legacy HTML and asset Cache-Control policies cannot be deleted in the
# same apply that detaches them from CloudFront. Forget them after detaching so
# the distribution update is not blocked by ResponseHeadersPolicyInUse.
#
# The CloudWatch access-logging resources moved from this module into
# cdn/cloudfront when logging gained the destination select. Without these
# blocks an upgrade plans create-then-destroy on identically named resources
# and the applies collide (log group "already exists", delivery source
# PutDeliverySource conflict).
################################################################################

moved {
  from = aws_cloudfront_function.this
  to   = aws_cloudfront_function.request_rewrite
}

moved {
  from = aws_cloudfront_function.request_rewrite
  to   = aws_cloudfront_function.rewrite
}

removed {
  from = aws_cloudfront_response_headers_policy.html

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_cloudfront_response_headers_policy.assets

  lifecycle {
    destroy = false
  }
}

moved {
  from = aws_cloudwatch_log_group.access_logs
  to   = module.cdn.aws_cloudwatch_log_group.access_logs
}

moved {
  from = aws_cloudwatch_log_delivery_source.access_logs
  to   = module.cdn.aws_cloudwatch_log_delivery_source.access_logs
}

moved {
  from = aws_cloudwatch_log_delivery_destination.access_logs
  to   = module.cdn.aws_cloudwatch_log_delivery_destination.access_logs
}

moved {
  from = aws_cloudwatch_log_delivery.access_logs
  to   = module.cdn.aws_cloudwatch_log_delivery.access_logs
}
